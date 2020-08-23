package Parse::PMFile;

sub __clean_eval { eval $_[0] } # needs to be here (RT#101273)

use strict;
use warnings;
use Safe;
use JSON::PP ();
use Dumpvalue;
use version ();
use File::Spec ();

our $VERSION = '0.42';
our $VERBOSE = 0;
our $ALLOW_DEV_VERSION = 0;
our $FORK = 0;
our $UNSAFE = $] < 5.010000 ? 1 : 0;

sub new {
    my ($class, $meta, $opts) = @_;
    bless {%{ $opts || {} }, META_CONTENT => $meta}, $class;
}

# from PAUSE::pmfile::examine_fio
sub parse {
    my ($self, $pmfile) = @_;

    $pmfile =~ s|\\|/|g;

    my($filemtime) = (stat $pmfile)[9];
    $self->{MTIME} = $filemtime;
    $self->{PMFILE} = $pmfile;

    unless ($self->_version_from_meta_ok) {
        my $version;
        unless (eval { $version = $self->_parse_version; 1 }) {
          $self->_verbose(1, "error with version in $pmfile: $@");
          return;
        }

        $self->{VERSION} = $version;
        if ($self->{VERSION} =~ /^\{.*\}$/) {
            # JSON error message
        } elsif ($self->{VERSION} =~ /[_\s]/ && !$self->{ALLOW_DEV_VERSION} && !$ALLOW_DEV_VERSION){   # ignore developer releases and "You suck!"
            return;
        }
    }

    my($ppp) = $self->_packages_per_pmfile;
    my @keys_ppp = $self->_filter_ppps(sort keys %$ppp);
    $self->_verbose(1,"Will check keys_ppp[@keys_ppp]\n");

    #
    # Immediately after each package (pmfile) examined contact
    # the database
    #

    my ($package, %errors);
    my %checked_in;
  DBPACK: foreach $package (@keys_ppp) {
        # this part is taken from PAUSE::package::examine_pkg
        # and PAUSE::package::_pkg_name_insane
        if ($package !~ /^\w[\w\:\']*\w?\z/
         || $package !~ /\w\z/
         || $package =~ /:/ && $package !~ /::/
         || $package =~ /\w:\w/
         || $package =~ /:::/
        ){
            $self->_verbose(1,"Package[$package] did not pass the ultimate sanity check");
            delete $ppp->{$package};
            next;
        }

        if ($self->{USERID} && $self->{PERMISSIONS} && !$self->_perm_check($package)) {
            delete $ppp->{$package};
            next;
        }

        # Check that package name matches case of file name
        {
          my (undef, $module) = split m{/lib/}, $self->{PMFILE}, 2;
          if ($module) {
            $module =~ s{\.pm\z}{};
            $module =~ s{/}{::}g;

            if (lc $module eq lc $package && $module ne $package) {
              # warn "/// $self->{PMFILE} vs. $module vs. $package\n";
              $errors{$package} = {
                indexing_warning => "Capitalization of package ($package) does not match filename!",
                infile => $self->{PMFILE},
              };
            }
          }
        }

        my $pp = $ppp->{$package};
        if ($pp->{version} && $pp->{version} =~ /^\{.*\}$/) { # JSON parser error
            my $err = JSON::PP::decode_json($pp->{version});
            if ($err->{x_normalize}) {
                $errors{$package} = {
                    normalize => $err->{version},
                    infile => $pp->{infile},
                };
                $pp->{version} = "undef";
            } elsif ($err->{openerr}) {
                $pp->{version} = "undef";
                $self->_verbose(1,
                              qq{Parse::PMFile was not able to
        read the file. It issued the following error: C< $err->{r} >},
                              );
                $errors{$package} = {
                    open => $err->{r},
                    infile => $pp->{infile},
                };
            } else {
                $pp->{version} = "undef";
                $self->_verbose(1, 
                              qq{Parse::PMFile was not able to
        parse the following line in that file: C< $err->{line} >

        Note: the indexer is running in a Safe compartement and cannot
        provide the full functionality of perl in the VERSION line. It
        is trying hard, but sometime it fails. As a workaround, please
        consider writing a META.yml that contains a 'provides'
        attribute or contact the CPAN admins to investigate (yet
        another) workaround against "Safe" limitations.)},

                              );
                $errors{$package} = {
                    parse_version => $err->{line},
                    infile => $err->{file},
                };
            }
        }

        # Sanity checks

        for (
            $package,
            $pp->{version},
        ) {
            if (!defined || /^\s*$/ || /\s/){  # for whatever reason I come here
                delete $ppp->{$package};
                next;            # don't screw up 02packages
            }
        }
        unless ($self->_version_ok($pp)) {
            $errors{$package} = {
                long_version => qq{Version string exceeds maximum allowed length of 16b: "$pp->{version}"},
                infile => $pp->{infile},
            };
            next;
        }
        $checked_in{$package} = $ppp->{$package};
    }                       # end foreach package

    return (wantarray && %errors) ? (\%checked_in, \%errors) : \%checked_in;
}

sub _version_ok {
    my ($self, $pp) = @_;
    return if length($pp->{version} || 0) > 16;
    return 1
}

sub _perm_check {
    my ($self, $package) = @_;
    my $userid = $self->{USERID};
    my $module = $self->{PERMISSIONS}->module_permissions($package);
    return 1 if !$module; # not listed yet
    return 1 if defined $module->m && $module->m eq $userid;
    return 1 if defined $module->f && $module->f eq $userid;
    return 1 if defined $module->c && grep {$_ eq $userid} @{$module->c};
    return;
}

# from PAUSE::pmfile;
sub _parse_version {
    my $self = shift;

    use strict;

    my $pmfile = $self->{PMFILE};
    my $tmpfile = File::Spec->catfile(File::Spec->tmpdir, "ParsePMFile$$" . rand(1000));

    my $pmcp = $pmfile;
    for ($pmcp) {
        s/([^\\](\\\\)*)@/$1\\@/g; # thanks to Raphael Manfredi for the
        # solution to escape @s and \
    }
    my($v);
    {

        package main; # seems necessary

        # XXX: do we need to fork as PAUSE does?
        # or, is alarm() just fine?
        my $pid;
        if ($self->{FORK} || $FORK) {
            $pid = fork();
            die "Can't fork: $!" unless defined $pid;
        }
        if ($pid) {
            waitpid($pid, 0);
            if (open my $fh, '<', $tmpfile) {
                $v = <$fh>;
            }
        } else {
            # XXX Limit Resources too

            my($comp) = Safe->new;
            my $eval = qq{
                local(\$^W) = 0;
                Parse::PMFile::_parse_version_safely("$pmcp");
            };
            $comp->permit("entereval"); # for MBARBON/Module-Info-0.30.tar.gz
            $comp->share("*Parse::PMFile::_parse_version_safely");
            $comp->share("*version::new");
            $comp->share("*version::numify");
            $comp->share_from('main', ['*version::',
                                        '*charstar::',
                                        '*Exporter::',
                                        '*DynaLoader::']);
            $comp->share_from('version', ['&qv']);
            $comp->permit(":base_math"); # atan2 (Acme-Pi)
            # $comp->permit("require"); # no strict!
            $comp->deny(qw/enteriter iter unstack goto/); # minimum protection against Acme::BadExample

            version->import('qv') if $self->{UNSAFE} || $UNSAFE;
            {
                no strict;
                $v = ($self->{UNSAFE} || $UNSAFE) ? eval $eval : $comp->reval($eval);
            }
            if ($@){ # still in the child process, out of Safe::reval
                my $err = $@;
                # warn ">>>>>>>err[$err]<<<<<<<<";
                if (ref $err) {
                    if ($err->{line} =~ /([\$*])([\w\:\']*)\bVERSION\b.*?\=(.*)/) {
                        local($^W) = 0;
                        my ($sigil, $vstr) = ($1, $3);
                        $self->_restore_overloaded_stuff(1) if $err->{line} =~ /use\s+version\b|version\->|qv\(/;
                        $v = ($self->{UNSAFE} || $UNSAFE) ? eval $vstr : $comp->reval($vstr);
                        $v = $$v if $sigil eq '*' && ref $v;
                    }
                    if ($@ or !$v) {
                        $self->_verbose(1, sprintf("reval failed: err[%s] for eval[%s]",
                                      JSON::PP::encode_json($err),
                                      $eval,
                                    ));
                        $v = JSON::PP::encode_json($err);
                    }
                } else {
                    $v = JSON::PP::encode_json({ openerr => $err });
                }
            }
            if (defined $v) {
                no warnings;
                $v = $v->numify if ref($v) =~ /^version(::vpp)?$/;
            } else {
                $v = "";
            }
            if ($self->{FORK} || $FORK) {
                open my $fh, '>:utf8', $tmpfile;
                print $fh $v;
                exit 0;
            } else {
                utf8::encode($v);
                # undefine empty $v as if read from the tmpfile
                $v = undef if defined $v && !length $v;
                $comp->erase;
                $self->_restore_overloaded_stuff;
            }
        }
    }
    unlink $tmpfile if ($self->{FORK} || $FORK) && -e $tmpfile;

    return $self->_normalize_version($v);
}

sub _restore_overloaded_stuff {
    my ($self, $used_version_in_safe) = @_;
    return if $self->{UNSAFE} || $UNSAFE;

    no strict 'refs';
    no warnings 'redefine';

    # version XS in CPAN
    my $restored;
    if ($INC{'version/vxs.pm'}) {
        *{'version::(""'} = \&version::vxs::stringify;
        *{'version::(0+'} = \&version::vxs::numify;
        *{'version::(cmp'} = \&version::vxs::VCMP;
        *{'version::(<=>'} = \&version::vxs::VCMP;
        *{'version::(bool'} = \&version::vxs::boolean;
        $restored = 1;
    }
    # version PP in CPAN
    if ($INC{'version/vpp.pm'}) {
        {
            package # hide from PAUSE
                charstar;
            overload->import;
        }
        if (!$used_version_in_safe) {
            package # hide from PAUSE
                version::vpp;
            overload->import;
        }
        unless ($restored) {
            *{'version::(""'} = \&version::vpp::stringify;
            *{'version::(0+'} = \&version::vpp::numify;
            *{'version::(cmp'} = \&version::vpp::vcmp;
            *{'version::(<=>'} = \&version::vpp::vcmp;
            *{'version::(bool'} = \&version::vpp::vbool;
        }
        *{'version::vpp::(""'} = \&version::vpp::stringify;
        *{'version::vpp::(0+'} = \&version::vpp::numify;
        *{'version::vpp::(cmp'} = \&version::vpp::vcmp;
        *{'version::vpp::(<=>'} = \&version::vpp::vcmp;
        *{'version::vpp::(bool'} = \&version::vpp::vbool;
        *{'charstar::(""'} = \&charstar::thischar;
        *{'charstar::(0+'} = \&charstar::thischar;
        *{'charstar::(++'} = \&charstar::increment;
        *{'charstar::(--'} = \&charstar::decrement;
        *{'charstar::(+'} = \&charstar::plus;
        *{'charstar::(-'} = \&charstar::minus;
        *{'charstar::(*'} = \&charstar::multiply;
        *{'charstar::(cmp'} = \&charstar::cmp;
        *{'charstar::(<=>'} = \&charstar::spaceship;
        *{'charstar::(bool'} = \&charstar::thischar;
        *{'charstar::(='} = \&charstar::clone;
        $restored = 1;
    }
    # version in core
    if (!$restored) {
        *{'version::(""'} = \&version::stringify;
        *{'version::(0+'} = \&version::numify;
        *{'version::(cmp'} = \&version::vcmp;
        *{'version::(<=>'} = \&version::vcmp;
        *{'version::(bool'} = \&version::boolean;
    }
}

# from PAUSE::pmfile;
sub _packages_per_pmfile {
    my $self = shift;

    my $ppp = {};
    my $pmfile = $self->{PMFILE};
    my $filemtime = $self->{MTIME};
    my $version = $self->{VERSION};

    open my $fh, "<", "$pmfile" or return $ppp;

    local $/ = "\n";
    my $inpod = 0;

  PLINE: while (<$fh>) {
        chomp;
        my($pline) = $_;
        $inpod = $pline =~ /^=(?!cut)/ ? 1 :
            $pline =~ /^=cut/ ? 0 : $inpod;
        next if $inpod;
        next if substr($pline,0,4) eq "=cut";

        $pline =~ s/\#.*//;
        next if $pline =~ /^\s*$/;
        if ($pline =~ /^__(?:END|DATA)__\b/
            and $pmfile !~ /\.PL$/   # PL files may well have code after __DATA__
            ){
            last PLINE;
        }

        my $pkg;
        my $strict_version;

        if (
            $pline =~ m{
                      # (.*) # takes too much time if $pline is long
                      #(?<![*\$\\@%&]) # no sigils
                      ^[\s\{;]*
                      \bpackage\s+
                      ([\w\:\']+)
                      \s*
                      (?: $ | [\}\;] | \{ | \s+($version::STRICT) )
                    }x) {
            $pkg = $1;
            $strict_version = $2;
            if ($pkg eq "DB"){
                # XXX if pumpkin and perl make him comaintainer! I
                # think I always made the pumpkins comaint on DB
                # without further ado (?)
                next PLINE;
            }
        }

        if ($pkg) {
            # Found something

            # from package
            $pkg =~ s/\'/::/g;
            next PLINE unless $pkg =~ /^[A-Za-z]/;
            next PLINE unless $pkg =~ /\w$/;
            next PLINE if $pkg eq "main";
            # Perl::Critic::Policy::TestingAndDebugging::ProhibitShebangWarningsArg
            # database for modid in mods, package in packages, package in perms
            # alter table mods modify modid varchar(128) binary NOT NULL default '';
            # alter table packages modify package varchar(128) binary NOT NULL default '';
            next PLINE if length($pkg) > 128;
            #restriction
            $ppp->{$pkg}{parsed}++;
            $ppp->{$pkg}{infile} = $pmfile;
            if ($self->_simile($pmfile,$pkg)) {
                $ppp->{$pkg}{simile} = $pmfile;
                if ($self->_version_from_meta_ok) {
                    my $provides = $self->{META_CONTENT}{provides};
                    if (exists $provides->{$pkg}) {
                        if (defined $provides->{$pkg}{version}) {
                            my $v = $provides->{$pkg}{version};
                            if ($v =~ /[_\s]/ && !$self->{ALLOW_DEV_VERSION} && !$ALLOW_DEV_VERSION){   # ignore developer releases and "You suck!"
                                next PLINE;
                            }

                            unless (eval { $version = $self->_normalize_version($v); 1 }) {
                              $self->_verbose(1, "error with version in $pmfile: $@");
                              next;

                            }
                            $ppp->{$pkg}{version} = $version;
                        } else {
                            $ppp->{$pkg}{version} = "undef";
                        }
                    }
                } else {
                    if (defined $strict_version){
                        $ppp->{$pkg}{version} = $strict_version ;
                    } else {
                        $ppp->{$pkg}{version} = defined $version ? $version : "";
                    }
                    no warnings;
                    if ($version eq 'undef') {
                        $ppp->{$pkg}{version} = $version unless defined $ppp->{$pkg}{version};
                    } else {
                        $ppp->{$pkg}{version} =
                            $version
                                if $version
                                    > $ppp->{$pkg}{version} ||
                                        $version
                                            gt $ppp->{$pkg}{version};
                    }
                }
            } else {        # not simile
                #### it comes later, it would be nonsense
                #### to set to "undef". MM_Unix gives us
                #### the best we can reasonably consider
                $ppp->{$pkg}{version} =
                    $version
                        unless defined $ppp->{$pkg}{version} &&
                            length($ppp->{$pkg}{version});
            }
            $ppp->{$pkg}{filemtime} = $filemtime;
        } else {
            # $self->_verbose(2,"no pkg found");
        }
    }

    close $fh;
    $ppp;
}

# from PAUSE::pmfile;
{
    no strict;
    sub _parse_version_safely {
        my($parsefile) = @_;
        my $result;
        local *FH;
        local $/ = "\n";
        open(FH,$parsefile) or die "Could not open '$parsefile': $!";
        my $inpod = 0;
        while (<FH>) {
            $inpod = /^=(?!cut)/ ? 1 : /^=cut/ ? 0 : $inpod;
            next if $inpod || /^\s*#/;
            last if /^__(?:END|DATA)__\b/; # fails on quoted __END__ but this is rare -> __END__ in the middle of a line is rarer
            chop;

            if (my ($ver) = /package \s+ \S+ \s+ (\S+) \s* [;{]/x) {
              # XXX: should handle this better if version is bogus -- rjbs,
              # 2014-03-16
              return $ver if version::is_lax($ver);
            }

            # next unless /\$(([\w\:\']*)\bVERSION)\b.*\=/;
            next unless /(?<!\\)([\$*])(([\w\:\']*)\bVERSION)\b.*(?<![!><=])\=(?![=>])/;
            my $current_parsed_line = $_;
            my $eval = qq{
                package #
                    ExtUtils::MakeMaker::_version;

                local $1$2;
                \$$2=undef; do {
                    $_
                }; \$$2
            };
            local $^W = 0;
            local $SIG{__WARN__} = sub {};
            $result = __clean_eval($eval);
            # warn "current_parsed_line[$current_parsed_line]\$\@[$@]";
            if ($@ or !defined $result){
                die +{
                      eval => $eval,
                      line => $current_parsed_line,
                      file => $parsefile,
                      err => $@,
                      };
            }
            last;
        } #;
        close FH;

        $result = "undef" unless defined $result;
        if ((ref $result) =~ /^version(?:::vpp)?\b/) {
            no warnings;
            $result = $result->numify;
        }
        return $result;
    }
}

# from PAUSE::pmfile;
sub _filter_ppps {
    my($self,@ppps) = @_;
    my @res;

    # very similar code is in PAUSE::dist::filter_pms
  MANI: for my $ppp ( @ppps ) {
        if ($self->{META_CONTENT}){
            my $no_index = $self->{META_CONTENT}{no_index}
                            || $self->{META_CONTENT}{private}; # backward compat
            if (ref($no_index) eq 'HASH') {
                my %map = (
                            package => qr{\z},
                            namespace => qr{::},
                          );
                for my $k (qw(package namespace)) {
                    next unless my $v = $no_index->{$k};
                    my $rest = $map{$k};
                    if (ref $v eq "ARRAY") {
                        for my $ve (@$v) {
                            $ve =~ s|::$||;
                            if ($ppp =~ /^$ve$rest/){
                                $self->_verbose(1,"Skipping ppp[$ppp] due to ve[$ve]");
                                next MANI;
                            } else {
                                $self->_verbose(1,"NOT skipping ppp[$ppp] due to ve[$ve]");
                            }
                        }
                    } else {
                        $v =~ s|::$||;
                        if ($ppp =~ /^$v$rest/){
                            $self->_verbose(1,"Skipping ppp[$ppp] due to v[$v]");
                            next MANI;
                        } else {
                            $self->_verbose(1,"NOT skipping ppp[$ppp] due to v[$v]");
                        }
                    }
                }
            } else {
                $self->_verbose(1,"No keyword 'no_index' or 'private' in META_CONTENT");
            }
        } else {
            # $self->_verbose(1,"no META_CONTENT"); # too noisy
        }
        push @res, $ppp;
    }
    $self->_verbose(1,"Result of filter_ppps: res[@res]");
    @res;
}

# from PAUSE::pmfile;
sub _simile {
    my($self,$file,$package) = @_;
    # MakeMaker gives them the chance to have the file Simple.pm in
    # this directory but have the package HTML::Simple in it.
    # Afaik, they wouldn't be able to do so with deeper nested packages
    $file =~ s|.*/||;
    $file =~ s|\.pm(?:\.PL)?||;
    my $ret = $package =~ m/\b\Q$file\E$/;
    $ret ||= 0;
    unless ($ret) {
        # Apache::mod_perl_guide stuffs it into Version.pm
        $ret = 1 if lc $file eq 'version';
    }
    $self->_verbose(1,"Result of simile(): file[$file] package[$package] ret[$ret]\n");
    $ret;
}

# from PAUSE::pmfile
sub _normalize_version {
    my($self,$v) = @_;
    $v = "undef" unless defined $v;
    my $dv = Dumpvalue->new;
    my $sdv = $dv->stringify($v,1); # second argument prevents ticks
    $self->_verbose(1,"Result of normalize_version: sdv[$sdv]\n");

    return $v if $v eq "undef";
    return $v if $v =~ /^\{.*\}$/; # JSON object
    $v =~ s/^\s+//;
    $v =~ s/\s+\z//;
    if ($v =~ /_/) {
        # XXX should pass something like EDEVELOPERRELEASE up e.g.
        # SIXTEASE/XML-Entities-0.0306.tar.gz had nothing but one
        # such modules and the mesage was not helpful that "nothing
        # was found".
        return $v ;
    }
    if (!version::is_lax($v)) {
        return JSON::PP::encode_json({ x_normalize => 'version::is_lax failed', version => $v });
    }
    # may warn "Integer overflow"
    my $vv = eval { no warnings; version->new($v)->numify };
    if ($@) {
        # warn "$v: $@";
        return JSON::PP::encode_json({ x_normalize => $@, version => $v });
        # return "undef";
    }
    if ($vv eq $v) {
        # the boring 3.14
    } else {
        my $forced = $self->_force_numeric($v);
        if ($forced eq $vv) {
        } elsif ($forced =~ /^v(.+)/) {
            # rare case where a v1.0.23 slipped in (JANL/w3mir-1.0.10.tar.gz)
            no warnings;
            $vv = version->new($1)->numify;
        } else {
            # warn "Unequal forced[$forced] and vv[$vv]";
            if ($forced == $vv) {
                # the trailing zeroes would cause unnecessary havoc
                $vv = $forced;
            }
        }
    }
    return $vv;
}

# from PAUSE::pmfile;
sub _force_numeric {
    my($self,$v) = @_;
    $v = $self->_readable($v);

    if (
        $v =~
        /^(\+?)(\d*)(\.(\d*))?/ &&
        # "$2$4" ne ''
        (
          defined $2 && length $2
          ||
          defined $4 && length $4
        )
        ) {
        my $two = defined $2 ? $2 : "";
        my $three = defined $3 ? $3 : "";
        $v = "$two$three";
    }
    # no else branch! We simply say, everything else is a string.
    $v;
}

# from PAUSE::dist
sub _version_from_meta_ok {
  my($self) = @_;
  return $self->{VERSION_FROM_META_OK} if exists $self->{VERSION_FROM_META_OK};
  my $c = $self->{META_CONTENT};

  # If there's no provides hash, we can't get our module versions from the
  # provides hash! -- rjbs, 2012-03-31
  return($self->{VERSION_FROM_META_OK} = 0) unless $c->{provides};

  # Some versions of Module::Build geneated an empty provides hash.  If we're
  # *not* looking at a Module::Build-generated metafile, then it's okay.
  my ($mb_v) = (defined $c->{generated_by} ? $c->{generated_by} : '') =~ /Module::Build version ([\d\.]+)/;
  return($self->{VERSION_FROM_META_OK} = 1) unless $mb_v;

  # ??? I don't know why this is here.
  return($self->{VERSION_FROM_META_OK} = 1) if $mb_v eq '0.250.0';

  if ($mb_v >= 0.19 && $mb_v < 0.26 && ! keys %{$c->{provides}}) {
      # RSAVAGE/Javascript-SHA1-1.01.tgz had an empty provides hash. Ron
      # did not find the reason why this happened, but let's not go
      # overboard, 0.26 seems a good threshold from the statistics: there
      # are not many empty provides hashes from 0.26 up.
      return($self->{VERSION_FROM_META_OK} = 0);
  }

  # We're not in the suspect range of M::B versions.  It's good to go.
  return($self->{VERSION_FROM_META_OK} = 1);
}

sub _verbose {
    my($self,$level,@what) = @_;
    warn @what if $level <= ((ref $self && $self->{VERBOSE}) || $VERBOSE);
}

# all of the following methods are stripped from CPAN::Version
# (as of version 5.5001, bundled in CPAN 2.03), and slightly
# modified (ie. made private, as well as CPAN->debug(...) are
# replaced with $self->_verbose(9, ...).)

# CPAN::Version::vcmp courtesy Jost Krieger
sub _vcmp {
    my($self,$l,$r) = @_;
    local($^W) = 0;
    $self->_verbose(9, "l[$l] r[$r]");

    return 0 if $l eq $r; # short circuit for quicker success

    for ($l,$r) {
        s/_//g;
    }
    $self->_verbose(9, "l[$l] r[$r]");
    for ($l,$r) {
        next unless tr/.// > 1 || /^v/;
        s/^v?/v/;
        1 while s/\.0+(\d)/.$1/; # remove leading zeroes per group
    }
    $self->_verbose(9, "l[$l] r[$r]");
    if ($l=~/^v/ <=> $r=~/^v/) {
        for ($l,$r) {
            next if /^v/;
            $_ = $self->_float2vv($_);
        }
    }
    $self->_verbose(9, "l[$l] r[$r]");
    my $lvstring = "v0";
    my $rvstring = "v0";
    if ($] >= 5.006
     && $l =~ /^v/
     && $r =~ /^v/) {
        $lvstring = $self->_vstring($l);
        $rvstring = $self->_vstring($r);
        $self->_verbose(9, sprintf "lv[%vd] rv[%vd]", $lvstring, $rvstring);
    }

    return (
            ($l ne "undef") <=> ($r ne "undef")
            ||
            $lvstring cmp $rvstring
            ||
            $l <=> $r
            ||
            $l cmp $r
    );
}

sub _vgt {
    my($self,$l,$r) = @_;
    $self->_vcmp($l,$r) > 0;
}

sub _vlt {
    my($self,$l,$r) = @_;
    $self->_vcmp($l,$r) < 0;
}

sub _vge {
    my($self,$l,$r) = @_;
    $self->_vcmp($l,$r) >= 0;
}

sub _vle {
    my($self,$l,$r) = @_;
    $self->_vcmp($l,$r) <= 0;
}

sub _vstring {
    my($self,$n) = @_;
    $n =~ s/^v// or die "Parse::PMFile::_vstring() called with invalid arg [$n]";
    pack "U*", split /\./, $n;
}

# vv => visible vstring
sub _float2vv {
    my($self,$n) = @_;
    my($rev) = int($n);
    $rev ||= 0;
    my($mantissa) = $n =~ /\.(\d{1,12})/; # limit to 12 digits to limit
                                          # architecture influence
    $mantissa ||= 0;
    $mantissa .= "0" while length($mantissa)%3;
    my $ret = "v" . $rev;
    while ($mantissa) {
        $mantissa =~ s/(\d{1,3})// or
            die "Panic: length>0 but not a digit? mantissa[$mantissa]";
        $ret .= ".".int($1);
    }
    # warn "n[$n]ret[$ret]";
    $ret =~ s/(\.0)+/.0/; # v1.0.0 => v1.0
    $ret;
}

sub _readable {
    my($self,$n) = @_;
    $n =~ /^([\w\-\+\.]+)/;

    return $1 if defined $1 && length($1)>0;
    # if the first user reaches version v43, he will be treated as "+".
    # We'll have to decide about a new rule here then, depending on what
    # will be the prevailing versioning behavior then.

    if ($] < 5.006) { # or whenever v-strings were introduced
        # we get them wrong anyway, whatever we do, because 5.005 will
        # have already interpreted 0.2.4 to be "0.24". So even if he
        # indexer sends us something like "v0.2.4" we compare wrongly.

        # And if they say v1.2, then the old perl takes it as "v12"

        $self->_verbose(9, "Suspicious version string seen [$n]\n");
        return $n;
    }
    my $better = sprintf "v%vd", $n;
    $self->_verbose(9, "n[$n] better[$better]");
    return $better;
}

1;

__END__

=head1 NAME

Parse::PMFile - parses .pm file as PAUSE does

=head1 SYNOPSIS

    use Parse::PMFile;

    my $parser = Parse::PMFile->new($metadata, {VERBOSE => 1});
    my $packages_info = $parser->parse($pmfile);

    # if you need info about invalid versions
    my ($packages_info, $errors) = $parser->parse($pmfile);

    # to check permissions
    my $parser = Parse::PMFile->new($metadata, {
        USERID => 'ISHIGAKI',
        PERMISSIONS => PAUSE::Permissions->new,
    });

=head1 DESCRIPTION

The most of the code of this module is taken from the PAUSE code as of April 2013 almost verbatim. Thus, the heart of this module should be quite stable. However, I made it not to use pipe ("-|") as well as I stripped database-related code. If you encounter any issue, that's most probably because of my modification.

This module doesn't provide features to extract a distribution or parse meta files intentionally.

=head1 METHODS

=head2 new

creates an object. You can also pass a hashref taken from META.yml etc, and an optional hashref. Options are:

=over 4

=item ALLOW_DEV_VERSION

Parse::PMFile usually ignores a version with an underscore as PAUSE does (because it's for a developer release, and should not be indexed). Set this option to true if you happen to need to keep such a version for better analysis.

=item VERBOSE

Set this to true if you need to know some details.

=item FORK

As of version 0.17, Parse::PMFile stops forking while parsing a version for better performance. Parse::PMFile should return the same result no matter how this option is set, but if you do care, set this to true to fork as PAUSE does.

=item USERID, PERMISSIONS

As of version 0.21, Parse::PMFile checks permissions of a package if both USERID and PERMISSIONS (which should be an instance of L<PAUSE::Permissions>) are provided. Unauthorized packages are removed.

=item UNSAFE

Parse::PMFile usually parses a module version in a Safe compartment. However, this approach doesn't work smoothly under older perls (prior to 5.10) plus some combinations of recent versions of Safe.pm (2.24 and above) and version.pm (0.9905 and above) for various reasons. As of version 0.27, Parse::PMFile simply uses C<eval> to parse a version under older perls. If you want it to use always C<eval> (even under recent perls), set this to true.

=back

=head2 parse

takes a path to a .pm file, and returns a hash reference that holds information for package(s) found in the file.

=head1 SEE ALSO

L<Parse::LocalDistribution>, L<PAUSE::Permissions>

Most part of this module is derived from PAUSE and CPAN::Version.

L<https://github.com/andk/pause>

L<https://github.com/andk/cpanpm>

=head1 AUTHOR

Andreas Koenig E<lt>andreas.koenig@anima.deE<gt>

Kenichi Ishigaki, E<lt>ishigaki@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 1995 - 2013 by Andreas Koenig E<lt>andk@cpan.orgE<gt> for most of the code.

Copyright 2013 by Kenichi Ishigaki for some.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
