package App::cpm::Master;
use strict;
use warnings;

use App::cpm::CircularDependency;
use App::cpm::Distribution;
use App::cpm::Job;
use App::cpm::Logger;
use App::cpm::version;
use CPAN::DistnameInfo;
use IO::Handle;
use Module::Metadata;

sub new {
    my ($class, %option) = @_;
    my $self = bless {
        %option,
        installed_distributions => 0,
        jobs => +{},
        distributions => +{},
        _fail_resolve => +{},
        _fail_install => +{},
        _is_installed => +{},
    }, $class;
    if ($self->{target_perl}) {
        require Module::CoreList;
        if (!exists $Module::CoreList::version{$self->{target_perl}}) {
            die "Module::CoreList does not have target perl $self->{target_perl} entry, abort.\n";
        }
        if (!exists $Module::CoreList::version{$]}) {
            die "Module::CoreList does not have our perl $] entry, abort.\n";
        }
    }
    if (!$self->{global}) {
        if (eval { require Module::CoreList }) {
            if (!exists $Module::CoreList::version{$]}) {
                die "Module::CoreList does not have our perl $] entry, abort.\n";
            }
            $self->{_has_corelist} = 1;
        } else {
            my $msg = "You don't have Module::CoreList. "
                    . "The local-lib may result in incomplete self-contained directory.";
            App::cpm::Logger->log(result => "WARN", message => $msg);
        }
    }
    $self;
}

sub fail {
    my $self = shift;

    my @fail_resolve = sort keys %{$self->{_fail_resolve}};
    my @fail_install = sort keys %{$self->{_fail_install}};
    my @not_installed = grep { !$self->{_fail_install}{$_->distfile} && !$_->installed } $self->distributions;
    return if !@fail_resolve && !@fail_install && !@not_installed;

    my $detector = App::cpm::CircularDependency->new;
    for my $dist (@not_installed) {
        my $req = $dist->requirements([qw(configure build test runtime)])->as_array;
        $detector->add($dist->distfile, $dist->provides, $req);
    }
    $detector->finalize;

    my $detected = $detector->detect;
    for my $distfile (sort keys %$detected) {
        my $distvname = $self->distribution($distfile)->distvname;
        my @circular = @{$detected->{$distfile}};
        my $msg = join " -> ", map { $self->distribution($_)->distvname } @circular;
        local $self->{logger}{context} = $distvname;
        $self->{logger}->log("Detected circular dependencies $msg");
        $self->{logger}->log("Failed to install distribution");
    }
    for my $dist (sort { $a->distvname cmp $b->distvname } grep { !$detected->{$_->distfile} } @not_installed) {
        local $self->{logger}{context} = $dist->distvname;
        $self->{logger}->log("Failed to install distribution, "
                            ."because of installing some dependencies failed");
    }

    my @name = (
        (map { CPAN::DistnameInfo->new($_)->distvname || $_ } @fail_install),
        (map { $_->distvname } @not_installed),
    );
    { resolve => \@fail_resolve, install => [sort @name] };
}

sub jobs { values %{shift->{jobs}} }

sub add_job {
    my ($self, %job) = @_;
    my $new = App::cpm::Job->new(%job);
    if (grep { $_->equals($new) } $self->jobs) {
        return 0;
    } else {
        $self->{jobs}{$new->uid} = $new;
        return 1;
    }
}

sub get_job {
    my $self = shift;
    if (my @job = grep { !$_->in_charge } $self->jobs) {
        return @job;
    }
    $self->_calculate_jobs;
    return unless $self->jobs;
    if (my @job = grep { !$_->in_charge } $self->jobs) {
        return @job;
    }
    return;
}

sub register_result {
    my ($self, $result) = @_;
    my ($job) = grep { $_->uid eq $result->{uid} } $self->jobs;
    die "Missing job that has uid=$result->{uid}" unless $job;

    %{$job} = %{$result}; # XXX

    my $logged = $self->info($job);
    my $method = "_register_@{[$job->{type}]}_result";
    $self->$method($job);
    $self->remove_job($job);
    $self->_show_progress if $logged && $self->{show_progress};

    return 1;
}

sub info {
    my ($self, $job) = @_;
    my $type = $job->type;
    return if !$App::cpm::Logger::VERBOSE && $type ne "install";
    my $name = $job->distvname;
    my ($message, $optional);
    if ($type eq "resolve") {
        $message = $job->{package};
        $message .= " -> $name" . ($job->{ref} ? "\@$job->{ref}" : "") if $job->{ok};
        $optional = "from $job->{from}" if $job->{ok} and $job->{from};
    } else {
        $message = $name;
        $optional = "using cache" if $type eq "fetch" and $job->{using_cache};
        $optional = "using prebuilt" if $job->{prebuilt};
    }
    my $elapsed = defined $job->{elapsed} ? sprintf "(%.3fsec) ", $job->{elapsed} : "";

    App::cpm::Logger->log(
        pid => $job->{pid},
        type => $type,
        result => $job->{ok} ? "DONE" : "FAIL",
        message => "$elapsed$message",
        optional => $optional,
    );
    return 1;
}

sub _show_progress {
    my $self = shift;
    my $all = keys %{$self->{distributions}};
    my $num = $self->installed_distributions;
    print STDERR "--- $num/$all ---";
    STDERR->flush; # this is needed at least with perl <= 5.24
}

sub remove_job {
    my ($self, $job) = @_;
    delete $self->{jobs}{$job->uid};
}

sub distributions { values %{shift->{distributions}} }

sub distribution {
    my ($self, $distfile) = @_;
    $self->{distributions}{$distfile};
}

sub _calculate_jobs {
    my $self = shift;

    my @distributions
        = grep { !$self->{_fail_install}{$_->distfile} } $self->distributions;

    if (my @dists = grep { $_->resolved && !$_->registered } @distributions) {
        for my $dist (@dists) {
            $dist->registered(1);
            $self->add_job(
                type => "fetch",
                distfile => $dist->{distfile},
                source => $dist->source,
                uri => $dist->uri,
                ref => $dist->ref,
            );
        }
    }

    if (my @dists = grep { $_->fetched && !$_->registered } @distributions) {
        for my $dist (@dists) {
            local $self->{logger}->{context} = $dist->distvname;
            my $dist_requirements = $dist->requirements('configure')->as_array;
            my ($is_satisfied, @need_resolve) = $self->is_satisfied($dist_requirements);
            if ($is_satisfied) {
                $dist->registered(1);
                $self->add_job(
                    type => "configure",
                    meta => $dist->meta,
                    directory => $dist->directory,
                    distfile => $dist->{distfile},
                    source => $dist->source,
                    uri => $dist->uri,
                    distvname => $dist->distvname,
                );
            } elsif (@need_resolve and !$dist->deps_registered) {
                $dist->deps_registered(1);
                my $msg = sprintf "Found configure dependencies: %s",
                    join(", ", map { sprintf "%s (%s)", $_->{package}, $_->{version_range} || 0 }  @need_resolve);
                $self->{logger}->log($msg);
                my $ok = $self->_register_resolve_job(@need_resolve);
                $self->{_fail_install}{$dist->distfile}++ unless $ok;
            } elsif (!defined $is_satisfied) {
                my ($req) = grep { $_->{package} eq "perl" } @$dist_requirements;
                my $msg = sprintf "%s requires perl %s, but you have only %s",
                    $dist->distvname, $req->{version_range}, $self->{target_perl} || $];
                $self->{logger}->log($msg);
                App::cpm::Logger->log(result => "FAIL", message => $msg);
                $self->{_fail_install}{$dist->distfile}++;
            }
        }
    }

    if (my @dists = grep { $_->configured && !$_->registered } @distributions) {
        for my $dist (@dists) {
            local $self->{logger}->{context} = $dist->distvname;

            my @phase = qw(build test runtime);
            push @phase, 'configure' if $dist->prebuilt;
            my $dist_requirements = $dist->requirements(\@phase)->as_array;
            my ($is_satisfied, @need_resolve) = $self->is_satisfied($dist_requirements);
            if ($is_satisfied) {
                $dist->registered(1);
                $self->add_job(
                    type => "install",
                    meta => $dist->meta,
                    distdata => $dist->distdata,
                    directory => $dist->directory,
                    distfile => $dist->{distfile},
                    uri => $dist->uri,
                    static_builder => $dist->static_builder,
                    prebuilt => $dist->prebuilt,
                );
            } elsif (@need_resolve and !$dist->deps_registered) {
                $dist->deps_registered(1);
                my $msg = sprintf "Found dependencies: %s",
                    join(", ", map { sprintf "%s (%s)", $_->{package}, $_->{version_range} || 0 }  @need_resolve);
                $self->{logger}->log($msg);
                my $ok = $self->_register_resolve_job(@need_resolve);
                $self->{_fail_install}{$dist->distfile}++ unless $ok;
            } elsif (!defined $is_satisfied) {
                my ($req) = grep { $_->{package} eq "perl" } @$dist_requirements;
                my $msg = sprintf "%s requires perl %s, but you have only %s",
                    $dist->distvname, $req->{version_range}, $self->{target_perl} || $];
                $self->{logger}->log($msg);
                App::cpm::Logger->log(result => "FAIL", message => $msg);
                $self->{_fail_install}{$dist->distfile}++;
            }
        }
    }
}

sub _register_resolve_job {
    my ($self, @package) = @_;
    my $ok = 1;
    for my $package (@package) {
        if ($self->{_fail_resolve}{$package->{package}}
            || $self->{_fail_install}{$package->{package}}
        ) {
            $ok = 0;
            next;
        }

        $self->add_job(
            type => "resolve",
            package => $package->{package},
            version_range => $package->{version_range},
        );
    }
    return $ok;
}

sub is_satisfied_perl_version {
    my ($self, $version_range) = @_;
    App::cpm::version->parse($self->{target_perl} || $])->satisfy($version_range);
}

sub is_installed {
    my ($self, $package, $version_range) = @_;
    my $wantarray = wantarray;
    if (exists $self->{_is_installed}{$package}) {
        if ($self->{_is_installed}{$package}->satisfy($version_range)) {
            return $wantarray ? (1, $self->{_is_installed}{$package}) : 1;
        }
    }
    my $info = Module::Metadata->new_from_module($package, inc => $self->{search_inc});
    return unless $info;

    if (!$self->{global} and $self->{_has_corelist} and $self->_in_core_inc($info->filename)) {
        # https://github.com/miyagawa/cpanminus/blob/7b574ede70cebce3709743ec1727f90d745e8580/Menlo-Legacy/lib/Menlo/CLI/Compat.pm#L1783-L1786
        # if found package in core inc,
        # but it does not list in CoreList,
        # we should treat it as not being installed
        return if !exists $Module::CoreList::version{$]}{$info->name};
    }
    my $current_version = $self->{_is_installed}{$package}
                        = App::cpm::version->parse($info->version);
    my $ok = $current_version->satisfy($version_range);
    $wantarray ? ($ok, $current_version) : $ok;
}

sub _in_core_inc {
    my ($self, $file) = @_;
    !!grep { $file =~ /^\Q$_/ } @{$self->{core_inc}};
}

sub is_core {
    my ($self, $package, $version_range) = @_;
    my $target_perl = $self->{target_perl};
    if (exists $Module::CoreList::version{$target_perl}{$package}) {
        if (!exists $Module::CoreList::version{$]}{$package}) {
            if (!$self->{_removed_core}{$package}++) {
                my $t = App::cpm::version->parse($target_perl)->normal;
                my $v = App::cpm::version->parse($])->normal;
                App::cpm::Logger->log(
                    result => "WARN",
                    message => "$package used to be core in $t, but not in $v, so will be installed",
                );
            }
            return;
        }
        return 1 unless $version_range;
        my $core_version = $Module::CoreList::version{$target_perl}{$package};
        return App::cpm::version->parse($core_version)->satisfy($version_range);
    }
    return;
}

# 0:     not satisfied, need wait for satisfying requirements
# 1:     satisfied, ready to install
# undef: not satisfied because of perl version
sub is_satisfied {
    my ($self, $requirements) = @_;
    my $is_satisfied = 1;
    my @need_resolve;
    my @distributions = $self->distributions;
    for my $req (@$requirements) {
        my ($package, $version_range) = @{$req}{qw(package version_range)};
        if ($package eq "perl") {
            $is_satisfied = undef if !$self->is_satisfied_perl_version($version_range);
            next;
        }
        next if $self->{target_perl} and $self->is_core($package, $version_range);
        next if $self->is_installed($package, $version_range);
        my ($resolved) = grep { $_->providing($package, $version_range) } @distributions;
        next if $resolved && $resolved->installed;

        $is_satisfied = 0 if defined $is_satisfied;
        if (!$resolved) {
            push @need_resolve, $req;
        }
    }
    return ($is_satisfied, @need_resolve);
}

sub add_distribution {
    my ($self, $distribution) = @_;
    my $distfile = $distribution->distfile;
    if (my $already = $self->{distributions}{$distfile}) {
        $already->overwrite_provide($_) for @{ $distribution->provides };
        return 0;
    } else {
        $self->{distributions}{$distfile} = $distribution;
        return 1;
    }
}

sub _register_resolve_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_resolve}{$job->{package}}++;
        return;
    }

    local $self->{logger}{context} = $job->{package};
    if ($job->{distfile} and $job->{distfile} =~ m{/perl-5[^/]+$}) {
        my $message = "Cannot upgrade core module $job->{package}.";
        $self->{logger}->log($message);
        App::cpm::Logger->log(
            result => "FAIL",
            type => "install",
            message => $message,
        );
        $self->{_fail_install}{$job->{package}}++; # XXX
        return;
    }

    if (!$job->{reinstall}) {
        my $want = $job->{version_range} || $job->{version};
        my ($ok, $local) = $self->is_installed($job->{package}, $want);
        if ($ok) {
            my $message = $job->{package} . (
                App::cpm::version->parse($job->{version}) != $local
                ? ", you already have $local"
                : " is up to date. ($local)"
            );
            $self->{logger}->log($message);
            App::cpm::Logger->log(
                result => "DONE",
                type => "install",
                message => $message,
            );
            return;
        }
    }

    my $provides = $job->{provides};
    if (!$provides or @$provides == 0) {
        my $version = App::cpm::version->parse($job->{version}) || 0;
        $provides = [{package => $job->{package}, version => $version}];
    }
    my $distribution = App::cpm::Distribution->new(
        source   => $job->{source},
        uri      => $job->{uri},
        provides => $provides,
        distfile => $job->{distfile},
        ref      => $job->{ref},
    );
    $self->add_distribution($distribution);
}

sub _register_fetch_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_install}{$job->distfile}++;
        return;
    }
    my $distribution = $self->distribution($job->distfile);
    $distribution->directory($job->{directory});
    $distribution->meta($job->{meta});
    $distribution->provides($job->{provides});

    if ($job->{prebuilt}) {
        $distribution->configured(1);
        $distribution->requirements($_ => $job->{requirements}{$_}) for keys %{$job->{requirements}};
        $distribution->prebuilt(1);
        local $self->{logger}{context} = $distribution->distvname;
        my $msg = join ", ", map { sprintf "%s (%s)", $_->{package}, $_->{version} || 0 } @{$distribution->provides};
        $self->{logger}->log("Distribution provides: $msg");
    } else {
        $distribution->fetched(1);
        $distribution->requirements($_ => $job->{requirements}{$_}) for keys %{$job->{requirements}};
    }
    return 1;
}

sub _register_configure_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_install}{$job->distfile}++;
        return;
    }
    my $distribution = $self->distribution($job->distfile);
    $distribution->configured(1);
    $distribution->requirements($_ => $job->{requirements}{$_}) for keys %{$job->{requirements}};
    $distribution->static_builder($job->{static_builder});
    $distribution->distdata($job->{distdata});

    # After configuring, the final "provides" is fixed.
    # So we need to re-define "provides" here
    my $p = $job->{distdata}{provides};
    my @provide = map +{ package => $_, version => $p->{$_}{version} }, sort keys %$p;
    $distribution->provides(\@provide);
    local $self->{logger}{context} = $distribution->distvname;
    my $msg = join ", ", map { sprintf "%s (%s)", $_->{package}, $_->{version} || 0 } @{$distribution->provides};
    $self->{logger}->log("Distribution provides: $msg");

    return 1;
}

sub _register_install_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_install}{$job->distfile}++;
        return;
    }
    my $distribution = $self->distribution($job->distfile);
    $distribution->installed(1);
    $self->{installed_distributions}++;
    return 1;
}

sub installed_distributions {
    shift->{installed_distributions};
}

1;
