package ExtUtils::MakeMaker::CPANfile;

use strict;
use warnings;
use ExtUtils::MakeMaker ();
use File::Spec::Functions qw/catfile rel2abs/;
use Module::CPANfile;
use version;

our $VERSION = "0.09";

sub import {
  my $class = shift;
  my $orig = \&ExtUtils::MakeMaker::WriteMakefile;
  my $writer = sub {
    my %params = @_;

    # Do nothing if not called from Makefile.PL
    my ($caller, $file, $line) = caller;
    (my $root = rel2abs($file)) =~ s/Makefile\.PL$//i or return;

    if (my $file = eval { Module::CPANfile->load(catfile($root, "cpanfile")) }) {
      my $prereqs = $file->prereqs;

      # Runtime requires => PREREQ_PM
      _merge(
        \%params,
        _get($prereqs, 'runtime', 'requires'),
        'PREREQ_PM',
      );

      # Build requires => BUILD_REQUIRES / PREREQ_PM
      _merge(
         \%params,
         _get($prereqs, 'build', 'requires'),
         _eumm('6.56') ? 'BUILD_REQUIRES' : 'PREREQ_PM',
      );

      # Test requires => TEST_REQUIRES / BUILD_REQUIRES / PREREQ_PM
      _merge(
         \%params,
         _get($prereqs, 'test', 'requires'),
         _eumm('6.63_03') ? 'TEST_REQUIRES' :
         _eumm('6.56') ? 'BUILD_REQUIRES' : 'PREREQ_PM',
      );

      # Configure requires => CONFIGURE_REQUIRES / ignored
      _merge(
         \%params,
         _get($prereqs, 'configure', 'requires'),
         _eumm('6.52') ? 'CONFIGURE_REQUIRES' : undef,
      );

      # Add myself to configure requires (if possible)
      _merge(
         \%params,
         {'ExtUtils::MakeMaker::CPANfile' => $VERSION},
         _eumm('6.52') ? 'CONFIGURE_REQUIRES' : undef,
      );

      # Set dynamic_config to 0 if not set explicitly
      if (!exists $params{META_ADD}{dynamic_config} &&
          !exists $params{META_MERGE}{dynamic_config}) {
          $params{META_MERGE}{dynamic_config} = 0;
      }

      # recommends, suggests, conflicts
      my $requires_2_0;
      for my $type (qw/recommends suggests conflicts/) {
          for my $phase (qw/configure build test runtime develop/) {
              my %tmp = %{$params{META_MERGE}{prereqs}{$phase} || {}};
              _merge(
                  \%tmp,
                  _get($prereqs, $phase, $type),
                  $type,
              );
              if ($tmp{$type}) {
                  $params{META_MERGE}{prereqs}{$phase} = \%tmp;
                  $requires_2_0 = 1;
              }
          }
      }
      if ($requires_2_0) { # for better recommends support
          # stash prereqs, which is already converted
          my $tmp_prereqs = delete $params{META_MERGE}{prereqs};

          require CPAN::Meta::Converter;
          for my $key (qw/META_ADD META_MERGE/) {
              next unless %{$params{$key} || {}};
              my $converter = CPAN::Meta::Converter->new($params{$key}, default_version => 1.4);
              $params{$key} = $converter->upgrade_fragment;
          }

          if ($params{META_MERGE}{prereqs}) {
              require CPAN::Meta::Requirements;
              for my $phase (keys %{$tmp_prereqs || {}}) {
                  for my $rel (keys %{$tmp_prereqs->{$phase} || {}}) {
                     my $req1 = CPAN::Meta::Requirements->from_string_hash($tmp_prereqs->{$phase}{$rel});
                     my $req2 = CPAN::Meta::Requirements->from_string_hash($params{META_MERGE}{prereqs}{$phase}{$rel});
                     $req1->add_requirements($req2);
                     $params{META_MERGE}{prereqs}{$phase} = $req1->as_string_hash;
                  }
              }
          } else {
              $params{META_MERGE}{prereqs} = $tmp_prereqs;
          }
      }

      # XXX: better to use also META_MERGE when applicable?

      # As a small bonus, remove params that the installed version
      # of EUMM doesn't know, so that we can always write them
      # in Makefile.PL without caring about EUMM version.
      # (EUMM warns if it finds unknown parameters.)
      # As EUMM 6.17 is our prereq, we can safely ignore the keys
      # defined before 6.17.
      {
        last if _eumm('6.66_03');
        if (my $r = delete $params{TEST_REQUIRES}) {
          _merge(\%params, $r, 'BUILD_REQUIRES');
        }
        last if _eumm('6.56');
        if (my $r = delete $params{BUILD_REQUIRES}) {
          _merge(\%params, $r, 'PREREQ_PM');
        }

        last if _eumm('6.52');
        delete $params{CONFIGURE_REQUIRES};

        last if _eumm('6.47_01');
        delete $params{MIN_PERL_VERSION};

        last if _eumm('6.45_01');
        delete $params{META_ADD};
        delete $params{META_MERGE};

        last if _eumm('6.30_01');
        delete $params{LICENSE};
      }
    } else {
        print "cpanfile is not available: $@\n";
        exit 0; # N/A
    }

    $orig->(%params);
  };
  {
    no warnings 'redefine';
    *main::WriteMakefile =
    *ExtUtils::MakeMaker::WriteMakefile = $writer;
  }
}

sub _eumm {
  my $version = shift;
  eval { ExtUtils::MakeMaker->VERSION($version) } ? 1 : 0;
}

sub _get {
  my $prereqs = shift;
  eval { $prereqs->requirements_for(@_)->as_string_hash };
}

sub _merge {
  my ($params, $requires, $key) = @_;

  return unless $key;

  for (keys %{$requires || {}}) {
    my $version = _normalize_version($requires->{$_});
    next unless defined $version;

    if (not exists $params->{$key}{$_}) {
      $params->{$key}{$_} = $version;
    } else {
      my $prev = $params->{$key}{$_};
      if (version->parse($prev) < version->parse($version)) {
        $params->{$key}{$_} = $version;
      }
    }
  }
}

sub _normalize_version {
  my $version = shift;

  # shortcuts
  return unless defined $version;
  return $version unless $version =~ /\s/;

  # TODO: better range handling
  $version =~ s/(?:>=|==)\s*//;
  $version =~ s/,.+$//;

  return $version unless $version =~ /\s/;
  return;
}

1;

__END__

=encoding utf-8

=head1 NAME

ExtUtils::MakeMaker::CPANfile - cpanfile support for EUMM

=head1 SYNOPSIS

    # Makefile.PL
    use ExtUtils::MakeMaker::CPANfile;
    
    WriteMakefile(
      NAME => 'Foo::Bar',
      AUTHOR => 'A.U.Thor <author@cpan.org>',
    );
    
    # cpanfile
    requires 'ExtUtils::MakeMaker' => '6.17';
    on test => sub {
      requires 'Test::More' => '0.88';
    };

=head1 DESCRIPTION

ExtUtils::MakeMaker::CPANfile loads C<cpanfile> in your distribution
and modifies parameters for C<WriteMakefile> in your Makefile.PL.
Just use it instead of L<ExtUtils::MakeMaker> (which should be
loaded internally), and prepare C<cpanfile>.

As of version 0.03, ExtUtils::MakeMaker::CPANfile also removes
WriteMakefile parameters that the installed version of
ExtUtils::MakeMaker doesn't know, to avoid warnings.

=head1 LIMITATION

=head2 complex version ranges

As of this writing, complex version ranges are simply ignored.

=head2 dynamic config

Strictly speaking, C<cpanfile> is a Perl script, and may have some
conditions in it. That said, you don't need to run Makefile.PL
to determine prerequisites in most cases. Hence, as of 0.06,
ExtUtils::MakeMaker::CPANfile sets C<dynamic_config> to false
by default. If you do need a CPAN installer to run Makefile.PL
to customize prerequisites dynamically, set C<dynamic_config>
to true explicitly (via META_ADD/META_MERGE).

=head1 FOR MODULE AUTHORS

Though the minimum version requirement of ExtUtils::MakeMaker is
arbitrary set to 6.17 (the one bundled in Perl 5.8.1), you need
at least EUMM 6.52 (with CONFIGURE_REQUIRES support) when you
release a distribution.

=head1 LICENSE

Copyright (C) Kenichi Ishigaki.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Kenichi Ishigaki E<lt>ishigaki@cpan.orgE<gt>

=cut

