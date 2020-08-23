package App::cpm::Tutorial;
use strict;
use warnings;

1;
__END__

=head1 NAME

App::cpm::Tutorial - How to use cpm

=head1 SYNOPSIS

  $ cpm install Module

=head1 DESCRIPTION

cpm is yet another CPAN client (like L<cpan>, L<cpanp>, and L<cpanm>),
which is fast!

=head2 How to install cpm

From CPAN:

  $ cpanm -nq App::cpm

Or, download a I<self-contained> cpm:

  $ curl -fsSL --compressed https://git.io/cpm > cpm
  $ chmod +x cpm
  $ ./cpm --version

  # you can even install modules without installing cpm
  $ curl -fsSL --compressed https://git.io/cpm | perl - install Plack

=head2 First step

  $ cpm install Plack

This command installs Plack into C<./local>, and you can use it by

  $ perl -I$PWD/local/lib/perl5 -MPlack -E 'say Plack->VERSION'

If you want to install modules into current INC instead of C<./local>,
then use C<--global/-g> option.

  $ cpm install --global Plack

By default, cpm outputs only C<DONE install Module> things.
If you want more verbose messages, use C<--verbose/-v> option.

  $ cpm install --verbose Plack

=head2 Second step

cpm can handle version range notation like L<cpanm>. Let's see some examples.

  $ cpm install Plack~'> 1.000, <= 2.000'
  $ cpm install Plack~'== 1.0030'
  $ cpm install Plack@1.0030  # this is an alias of ~'== 1.0030'

cpm can install dev releases (TRIAL releases).

  $ cpm install Moose@dev

  # if you prefer dev releases for not only Moose,
  # but also its dependencies, then use global --dev option
  $ cpm install --dev Moose

And cpm can install modules from git repositories directly.

  $ cpm install git://github.com/skaji/Carl.git

=head2 cpanfile and dist/url/mirror/git syntax

If you omit arguments, and there exists C<cpanfile> in the current directory,
then cpm loads modules from cpanfile, and install them

  $ cat cpanfile
  requires 'Moose', '2.000';
  requires 'Plack', '> 1.000, <= 2.000';
  $ cpm install

If you have C<cpanfile.snapshot>,
then cpm tries to resolve distribution names from it

  $ cpm install -v
  30186 DONE resolve (0.001sec) Plack -> Plack-1.0030 (from Snapshot)
  ...

cpm supports dist/url/mirror syntax in cpanfile just like cpanminus:

  requires 'Path::Class', 0.26,
    dist => "KWILLIAMS/Path-Class-0.26.tar.gz";

  # use dist + mirror
  requires 'Cookie::Baker',
    dist => "KAZEBURO/Cookie-Baker-0.08.tar.gz",
    mirror => "http://cpan.cpantesters.org/";

  # use the full URL
  requires 'Try::Tiny', 0.28,
    url => "http://backpan.perl.org/authors/id/E/ET/ETHER/Try-Tiny-0.28.tar.gz";

And yes, this is an experimental and fun part! cpm also supports git syntax in cpanfile.

  requires 'Carl', git => 'git://github.com/skaji/Carl.git';
  requires 'App::cpm', git => 'https://login:password@github.com/skaji/cpm.git';
  requires 'Perl::PrereqDistributionGatherer',
    git => 'https://github.com/skaji/Perl-PrereqDistributionGatherer',
    ref => '3850305'; # ref can be revision/branch/tag

Please note that to support git syntax in cpanfile wholly,
there are several TODOs.

=head2 Darkpan integration

There are CPAN modules that create I<darkpans>
(minicpan, CPAN mirror) such as L<CPAN::Mini>, L<OrePAN2>, L<Pinto>.

Such darkpans store distribution tarballs in

  DARKPAN/authors/id/A/AU/AUTHOR/Module-0.01.tar.gz

and create the I<de facto standard> index file C<02packages.details.txt.gz> in

  DARKPAN/modules/02packages.details.txt.gz

If you want to use cpm against such darkpans,
change the cpm resolver by C<--resolver/-r> option:

  $ cpm install --resolver 02packages,http://example.com/darkpan Module
  $ cpm install --resolver 02packages,file::///path/to/darkpan   Module

Sometimes, your darkpan is not whole CPAN mirror, but partial,
so some modules are missing in it.
Then append C<--resolver metadb> option to fall back to normal MetaDB resolver:

  $ cpm install \
     --resolver 02packages,http://example.com/darkpan \
     --resolver metadb \
     Module

If you host your own darkmetadb for your own darkpan, you can use it too.
Then append C<--resolver metadb> option to fall back to normal MetaDB resolver:

  $ cpm install \
     --resolver metadb,http://example.com/darkmetadb,http://example.com/darkpan \
     --resolver metadb \
     Module

=cut
