package Carton::CLI;
use strict;
use warnings;
use Config;
use Getopt::Long;
use Path::Tiny;
use Try::Tiny;
use Module::CoreList;
use Scalar::Util qw(blessed);

use Carton;
use Carton::Builder;
use Carton::Mirror;
use Carton::Snapshot;
use Carton::Util;
use Carton::Environment;
use Carton::Error;

use constant { SUCCESS => 0, INFO => 1, WARN => 2, ERROR => 3 };

our $UseSystem = 0; # 1 for unit testing

use Class::Tiny {
    verbose => undef,
    carton => sub { $_[0]->_build_carton },
    mirror => sub { $_[0]->_build_mirror },
};

sub _build_mirror {
    my $self = shift;
    Carton::Mirror->new($ENV{PERL_CARTON_MIRROR} || $Carton::Mirror::DefaultMirror);
}

sub run {
    my($self, @args) = @_;

    my @commands;
    my $p = Getopt::Long::Parser->new(
        config => [ "no_ignore_case", "pass_through" ],
    );
    $p->getoptionsfromarray(
        \@args,
        "h|help"    => sub { unshift @commands, 'help' },
        "v|version" => sub { unshift @commands, 'version' },
        "verbose!"  => sub { $self->verbose($_[1]) },
    );

    push @commands, @args;

    my $cmd = shift @commands || 'install';

    my $code = try {
        my $call = $self->can("cmd_$cmd")
            or Carton::Error::CommandNotFound->throw(error => "Could not find command '$cmd'");
        $self->$call(@commands);
        return 0;
    } catch {
        die $_ unless blessed $_ && $_->can('rethrow');

        if ($_->isa('Carton::Error::CommandExit')) {
            return $_->code || 255;
        } elsif ($_->isa('Carton::Error::CommandNotFound')) {
            warn $_->error, "\n\n";
            $self->cmd_usage;
            return 255;
        } elsif ($_->isa('Carton::Error')) {
            warn $_->error, "\n";
            return 255;
        }
    };

    return $code;
}

sub commands {
    my $self = shift;

    no strict 'refs';
    map { s/^cmd_//; $_ }
        grep { /^cmd_.*/ && $self->can($_) } sort keys %{__PACKAGE__."::"};
}

sub cmd_usage {
    my $self = shift;
    $self->print(<<HELP);
Usage: carton <command>

where <command> is one of:
  @{[ join ", ", $self->commands ]}

Run carton -h <command> for help.
HELP
}

sub parse_options {
    my($self, $args, @spec) = @_;
    my $p = Getopt::Long::Parser->new(
        config => [ "no_auto_abbrev", "no_ignore_case" ],
    );
    $p->getoptionsfromarray($args, @spec);
}

sub parse_options_pass_through {
    my($self, $args, @spec) = @_;

    my $p = Getopt::Long::Parser->new(
        config => [ "no_auto_abbrev", "no_ignore_case", "pass_through" ],
    );
    $p->getoptionsfromarray($args, @spec);

    # with pass_through keeps -- in args
    shift @$args if $args->[0] && $args->[0] eq '--';
}

sub printf {
    my $self = shift;
    my $type = pop;
    my($temp, @args) = @_;
    $self->print(sprintf($temp, @args), $type);
}

sub print {
    my($self, $msg, $type) = @_;
    my $fh = $type && $type >= WARN ? *STDERR : *STDOUT;
    print {$fh} $msg;
}

sub error {
    my($self, $msg) = @_;
    $self->print($msg, ERROR);
    Carton::Error::CommandExit->throw;
}

sub cmd_help {
    my $self = shift;
    my $module = $_[0] ? ("Carton::Doc::" . ucfirst $_[0]) : "Carton.pm";
    system "perldoc", $module;
}

sub cmd_version {
    my $self = shift;
    $self->print("carton $Carton::VERSION\n");
}

sub cmd_bundle {
    my($self, @args) = @_;

    my $env = Carton::Environment->build;
    $env->snapshot->load;

    $self->print("Bundling modules using @{[$env->cpanfile]}\n");

    my $builder = Carton::Builder->new(
        mirror => $self->mirror,
        cpanfile => $env->cpanfile,
    );
    $builder->bundle($env->install_path, $env->vendor_cache, $env->snapshot);

    $self->printf("Complete! Modules were bundled into %s\n", $env->vendor_cache, SUCCESS);
}

sub cmd_fatpack {
    my($self, @args) = @_;

    my $env = Carton::Environment->build;
    require Carton::Packer;
    Carton::Packer->new->fatpack_carton($env->vendor_bin);
}

sub cmd_install {
    my($self, @args) = @_;

    my($install_path, $cpanfile_path, @without);

    $self->parse_options(
        \@args,
        "p|path=s"    => \$install_path,
        "cpanfile=s"  => \$cpanfile_path,
        "without=s"   => sub { push @without, split /,/, $_[1] },
        "deployment!" => \my $deployment,
        "cached!"     => \my $cached,
    );

    my $env = Carton::Environment->build($cpanfile_path, $install_path);
    $env->snapshot->load_if_exists;

    if ($deployment && !$env->snapshot->loaded) {
        $self->error("--deployment requires cpanfile.snapshot: Run `carton install` and make sure cpanfile.snapshot is checked into your version control.\n");
    }

    my $builder = Carton::Builder->new(
        cascade => 1,
        mirror  => $self->mirror,
        without => \@without,
        cpanfile => $env->cpanfile,
    );

    # TODO: --without with no .lock won't fetch the groups, resulting in insufficient requirements

    if ($deployment) {
        $self->print("Installing modules using @{[$env->cpanfile]} (deployment mode)\n");
        $builder->cascade(0);
    } else {
        $self->print("Installing modules using @{[$env->cpanfile]}\n");
    }

    # TODO merge CPANfile git to mirror even if lock doesn't exist
    if ($env->snapshot->loaded) {
        my $index_file = $env->install_path->child("cache/modules/02packages.details.txt");
           $index_file->parent->mkpath;

        $env->snapshot->write_index($index_file);
        $builder->index($index_file);
    }

    if ($cached) {
        $builder->mirror(Carton::Mirror->new($env->vendor_cache));
    }

    $builder->install($env->install_path);

    unless ($deployment) {
        $env->cpanfile->load;
        $env->snapshot->find_installs($env->install_path, $env->cpanfile->requirements);
        $env->snapshot->save;
    }

    $self->print("Complete! Modules were installed into @{[$env->install_path]}\n", SUCCESS);
}

sub cmd_show {
    my($self, @args) = @_;

    my $env = Carton::Environment->build;
    $env->snapshot->load;

    for my $module (@args) {
        my $dist = $env->snapshot->find($module)
            or $self->error("Couldn't locate $module in cpanfile.snapshot\n");
        $self->print( $dist->name . "\n" );
    }
}

sub cmd_list {
    my($self, @args) = @_;

    my $format = 'name';

    $self->parse_options(
        \@args,
        "distfile" => sub { $format = 'distfile' },
    );

    my $env = Carton::Environment->build;
    $env->snapshot->load;

    for my $dist ($env->snapshot->distributions) {
        $self->print($dist->$format . "\n");
    }
}

sub cmd_tree {
    my($self, @args) = @_;

    my $env = Carton::Environment->build;
    $env->snapshot->load;
    $env->cpanfile->load;

    my %seen;
    my $dumper = sub {
        my($dependency, $reqs, $level) = @_;
        return if $level == 0;
        return Carton::Tree::STOP if $dependency->dist->is_core;
        return Carton::Tree::STOP if $seen{$dependency->distname}++;
        $self->printf( "%s%s (%s)\n", " " x ($level - 1), $dependency->module, $dependency->distname, INFO );
    };

    $env->tree->walk_down($dumper);
}

sub cmd_check {
    my($self, @args) = @_;

    my $cpanfile_path;
    $self->parse_options(
        \@args,
        "cpanfile=s"  => \$cpanfile_path,
    );

    my $env = Carton::Environment->build($cpanfile_path);
    $env->snapshot->load;
    $env->cpanfile->load;

    # TODO remove snapshot
    # TODO pass git spec to Requirements?
    my $merged_reqs = $env->tree->merged_requirements;

    my @missing;
    for my $module ($merged_reqs->required_modules) {
        my $install = $env->snapshot->find_or_core($module);
        if ($install) {
            unless ($merged_reqs->accepts_module($module => $install->version_for($module))) {
                push @missing, [ $module, 1, $install->version_for($module) ];
            }
        } else {
            push @missing, [ $module, 0 ];
        }
    }

    if (@missing) {
        $self->print("Following dependencies are not satisfied.\n", INFO);
        for my $missing (@missing) {
            my($module, $unsatisfied, $version) = @$missing;
            if ($unsatisfied) {
                $self->printf("  %s has version %s. Needs %s\n",
                              $module, $version, $merged_reqs->requirements_for_module($module), INFO);
            } else {
                $self->printf("  %s is not installed. Needs %s\n",
                              $module, $merged_reqs->requirements_for_module($module), INFO);
            }
        }
        $self->printf("Run `carton install` to install them.\n", INFO);
        Carton::Error::CommandExit->throw;
    } else {
        $self->print("cpanfile's dependencies are satisfied.\n", INFO);
    }
}

sub cmd_update {
    my($self, @args) = @_;

    my $env = Carton::Environment->build;
    $env->cpanfile->load;


    my $cpanfile = Module::CPANfile->load($env->cpanfile);
    @args = grep { $_ ne 'perl' } $env->cpanfile->required_modules unless @args;

    $env->snapshot->load;

    my @modules;
    for my $module (@args) {
        my $dist = $env->snapshot->find_or_core($module)
            or $self->error("Could not find module $module.\n");
        next if $dist->is_core;
        push @modules, "$module~" . $env->cpanfile->requirements_for_module($module);
    }

    return unless @modules;

    my $builder = Carton::Builder->new(
        mirror => $self->mirror,
        cpanfile => $env->cpanfile,
    );
    $builder->update($env->install_path, @modules);

    $env->snapshot->find_installs($env->install_path, $env->cpanfile->requirements);
    $env->snapshot->save;
}

sub cmd_run {
    my($self, @args) = @_;

    local $UseSystem = 1;
    $self->cmd_exec(@args);
}

sub cmd_exec {
    my($self, @args) = @_;

    my $env = Carton::Environment->build;
    $env->snapshot->load;

    # allows -Ilib
    @args = map { /^(-[I])(.+)/ ? ($1,$2) : $_ } @args;

    while (@args) {
        if ($args[0] eq '-I') {
            warn "exec -Ilib is deprecated. You might want to run: carton exec perl -Ilib ...\n";
            splice(@args, 0, 2);
        } else {
            last;
        }
    }

    $self->parse_options_pass_through(\@args); # to handle --

    unless (@args) {
        $self->error("carton exec needs a command to run.\n");
    }

    # PERL5LIB takes care of arch
    my $path = $env->install_path;
    local $ENV{PERL5LIB} = "$path/lib/perl5";
    local $ENV{PATH} = "$path/bin:$ENV{PATH}";

    if ($UseSystem) {
        system @args;
    } else {
        exec @args;
        exit 127; # command not found
    }
}

1;
