package Carton;
use strict;
use 5.008_005;
use version; our $VERSION = version->declare("v1.0.34");

1;
__END__

=head1 NAME

Carton - Perl module dependency manager (aka Bundler for Perl)

=head1 SYNOPSIS

  # On your development environment
  > cat cpanfile
  requires 'Plack', '0.9980';
  requires 'Starman', '0.2000';

  > carton install
  > git add cpanfile cpanfile.snapshot
  > git commit -m "add Plack and Starman"

  # Other developer's machine, or on a deployment box
  > carton install
  > carton exec starman -p 8080 myapp.psgi

  # carton exec is optional
  > perl -Ilocal/lib/perl5 local/bin/starman -p 8080 myapp.psgi
  > PERL5LIB=/path/to/local/lib/perl5 /path/to/local/bin/starman -p 8080 myapp.psgi

=head1 AVAILABILITY

Carton only works with perl installation with the complete set of core
modules. If you use perl installed by a vendor package with modules
stripped from core, Carton is not expected to work correctly.

Also, Carton requires you to run your command/application with
C<carton exec> command or to include the I<local/lib/perl5> directory
in your Perl library search path (using C<PERL5LIB>, C<-I>, or
L<lib>).

=head1 DESCRIPTION

carton is a command line tool to track the Perl module dependencies
for your Perl application. Dependencies are declared using L<cpanfile>
format, and the managed dependencies are tracked in a
I<cpanfile.snapshot> file, which is meant to be version controlled,
and the snapshot file allows other developers of your application will
have the exact same versions of the modules.

For C<cpanfile> syntax, see L<cpanfile> documentation.

=head1 TUTORIAL

=head2 Initializing the environment

carton will use the I<local> directory to install modules into. You're
recommended to exclude these directories from the version control
system.

  > echo local/ >> .gitignore
  > git add cpanfile cpanfile.snapshot
  > git commit -m "Start using carton"

=head2 Tracking the dependencies

You can manage the dependencies of your application via C<cpanfile>.

  # cpanfile
  requires 'Plack', '0.9980';
  requires 'Starman', '0.2000';

And then you can install these dependencies via:

  > carton install

The modules are installed into your I<local> directory, and the
dependencies tree and version information are analyzed and saved into
I<cpanfile.snapshot> in your directory.

Make sure you add I<cpanfile> and I<cpanfile.snapshot> to your version
controlled repository and commit changes as you update
dependencies. This will ensure that other developers on your app, as
well as your deployment environment, use exactly the same versions of
the modules you just installed.

  > git add cpanfile cpanfile.snapshot
  > git commit -m "Added Plack and Starman"

=head2 Specifying a CPAN distribution

You can pin a module resolution to a specific distribution using a
combination of C<dist>, C<mirror> and C<url> options in C<cpanfile>.

  # specific distribution on PAUSE
  requires 'Plack', '== 0.9980',
    dist => 'MIYAGAWA/Plack-0.9980.tar.gz';

  # local mirror (darkpan)
  requires 'Plack', '== 0.9981',
    dist => 'MYCOMPANY/Plack-0.9981-p1.tar.gz',
    mirror => 'https://pause.local/';

  # URL
  requires 'Plack', '== 1.1000',
    url => 'https://pause.local/authors/id/M/MY/MYCOMPANY/Plack-1.1000.tar.gz';

=head2 Deploying your application

Once you've done installing all the dependencies, you can push your
application directory to a remote machine (excluding I<local> and
I<.carton>) and run the following command:

  > carton install --deployment

This will look at the I<cpanfile.snapshot> and install the exact same
versions of the dependencies into I<local>, and now your application
is ready to run.

The C<--deployment> flag makes sure that carton will only install
modules and versions available in your snapshot, and won't fallback to
query for CPAN Meta DB for missing modules.

=head2 Bundling modules

carton can bundle all the tarballs for your dependencies into a
directory so that you can even install dependencies that are not
available on CPAN, such as internal distribution aka DarkPAN.

  > carton bundle

will bundle these tarballs into I<vendor/cache> directory, and

  > carton install --cached

will install modules using this local cache. Combined with
C<--deployment> option, you can avoid querying for a database like
CPAN Meta DB or downloading files from CPAN mirrors upon deployment
time.

As of Carton v1.0.32, the bundle also includes a package index
allowing you to simply use L<cpanm> (which has a
L<standalone version|App::cpanminus/"Downloading the standalone executable">)
instead of installing Carton on a remote machine.

  > cpanm -L local --from "$PWD/vendor/cache" --installdeps --notest --quiet .

=head1 PERL VERSIONS

When you take a snapshot in one perl version and deploy on another
(different) version, you might have troubles with core modules.

The simplest solution, which might not work for everybody, is to use
the same version of perl in the development and deployment.

To enforce that, you're recommended to use L<plenv> and
C<.perl-version> to lock perl versions in development.

You can also specify the minimum perl required in C<cpanfile>:

  requires 'perl', '5.16.3';

and carton (and cpanm) will give you errors when deployed on hosts
with perl lower than the specified version.

=head1 COMMUNITY

=over 4

=item L<https://github.com/perl-carton/carton>

Code repository, Wiki and Issue Tracker

=item L<irc://irc.perl.org/#cpanm>

IRC chat room

=back

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 COPYRIGHT

Tatsuhiko Miyagawa 2011-

=head1 LICENSE

This software is licensed under the same terms as Perl itself.

=head1 SEE ALSO

L<cpanm>

L<cpanfile>

L<Bundler|http://gembundler.com/>

L<pip|http://pypi.python.org/pypi/pip>

L<npm|http://npmjs.org/>

L<perlrocks|https://github.com/gugod/perlrocks>

L<only>

=cut
