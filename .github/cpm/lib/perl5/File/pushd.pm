use strict;
use warnings;

package File::pushd;
# ABSTRACT: change directory temporarily for a limited scope

our $VERSION = '1.016';

our @EXPORT = qw( pushd tempd );
our @ISA    = qw( Exporter );

use Exporter;
use Carp;
use Cwd qw( getcwd abs_path );
use File::Path qw( rmtree );
use File::Temp qw();
use File::Spec;

use overload
  q{""}    => sub { File::Spec->canonpath( $_[0]->{_pushd} ) },
  fallback => 1;

#--------------------------------------------------------------------------#
# pushd()
#--------------------------------------------------------------------------#

sub pushd {
    # Called in void context?
    unless (defined wantarray) {
        warnings::warnif(void => 'Useless use of File::pushd::pushd in void context');
        return
    }

    my ( $target_dir, $options ) = @_;
    $options->{untaint_pattern} ||= qr{^([-+@\w./]+)$};

    $target_dir = "." unless defined $target_dir;
    croak "Can't locate directory $target_dir" unless -d $target_dir;

    my $tainted_orig = getcwd;
    my $orig;
    if ( $tainted_orig =~ $options->{untaint_pattern} ) {
        $orig = $1;
    }
    else {
        $orig = $tainted_orig;
    }

    my $tainted_dest;
    eval { $tainted_dest = $target_dir ? abs_path($target_dir) : $orig };
    croak "Can't locate absolute path for $target_dir: $@" if $@;

    my $dest;
    if ( $tainted_dest =~ $options->{untaint_pattern} ) {
        $dest = $1;
    }
    else {
        $dest = $tainted_dest;
    }

    if ( $dest ne $orig ) {
        chdir $dest or croak "Can't chdir to $dest\: $!";
    }

    my $self = bless {
        _pushd    => $dest,
        _original => $orig
      },
      __PACKAGE__;

    return $self;
}

#--------------------------------------------------------------------------#
# tempd()
#--------------------------------------------------------------------------#

sub tempd {
    # Called in void context?
    unless (defined wantarray) {
        warnings::warnif(void => 'Useless use of File::pushd::tempd in void context');
        return
    }

    my ($options) = @_;
    my $dir;
    eval { $dir = pushd( File::Temp::tempdir( CLEANUP => 0 ), $options ) };
    croak $@ if $@;
    $dir->{_tempd} = 1;
    $dir->{_owner} = $$;
    return $dir;
}

#--------------------------------------------------------------------------#
# preserve()
#--------------------------------------------------------------------------#

sub preserve {
    my $self = shift;
    return 1 if !$self->{"_tempd"};
    if ( @_ == 0 ) {
        return $self->{_preserve} = 1;
    }
    else {
        return $self->{_preserve} = $_[0] ? 1 : 0;
    }
}

#--------------------------------------------------------------------------#
# DESTROY()
# Revert to original directory as object is destroyed and cleanup
# if necessary
#--------------------------------------------------------------------------#

sub DESTROY {
    my ($self) = @_;
    my $orig = $self->{_original};
    chdir $orig if $orig; # should always be so, but just in case...
    if ( $self->{_tempd}
        && $self->{_owner} == $$
        && !$self->{_preserve} )
    {
        # don't destroy existing $@ if there is no error.
        my $err = do {
            local $@;
            eval { rmtree( $self->{_pushd} ) };
            $@;
        };
        carp $err if $err;
    }
}

1;

=pod

=encoding UTF-8

=head1 NAME

File::pushd - change directory temporarily for a limited scope

=head1 VERSION

version 1.016

=head1 SYNOPSIS

 use File::pushd;

 chdir $ENV{HOME};

 # change directory again for a limited scope
 {
     my $dir = pushd( '/tmp' );
     # working directory changed to /tmp
 }
 # working directory has reverted to $ENV{HOME}

 # tempd() is equivalent to pushd( File::Temp::tempdir )
 {
     my $dir = tempd();
 }

 # object stringifies naturally as an absolute path
 {
    my $dir = pushd( '/tmp' );
    my $filename = File::Spec->catfile( $dir, "somefile.txt" );
    # gives /tmp/somefile.txt
 }

=head1 DESCRIPTION

File::pushd does a temporary C<chdir> that is easily and automatically
reverted, similar to C<pushd> in some Unix command shells.  It works by
creating an object that caches the original working directory.  When the object
is destroyed, the destructor calls C<chdir> to revert to the original working
directory.  By storing the object in a lexical variable with a limited scope,
this happens automatically at the end of the scope.

This is very handy when working with temporary directories for tasks like
testing; a function is provided to streamline getting a temporary
directory from L<File::Temp>.

For convenience, the object stringifies as the canonical form of the absolute
pathname of the directory entered.

B<Warning>: if you create multiple C<pushd> objects in the same lexical scope,
their destruction order is not guaranteed and you might not wind up in the
directory you expect.

=head1 USAGE

 use File::pushd;

Using File::pushd automatically imports the C<pushd> and C<tempd> functions.

=head2 pushd

 {
     my $dir = pushd( $target_directory );
 }

Caches the current working directory, calls C<chdir> to change to the target
directory, and returns a File::pushd object.  When the object is
destroyed, the working directory reverts to the original directory.

The provided target directory can be a relative or absolute path. If
called with no arguments, it uses the current directory as its target and
returns to the current directory when the object is destroyed.

If the target directory does not exist or if the directory change fails
for some reason, C<pushd> will die with an error message.

Can be given a hashref as an optional second argument.  The only supported
option is C<untaint_pattern>, which is used to untaint file paths involved.
It defaults to {qr{^(L<-+@\w./>+)$}}, which is reasonably restrictive (e.g.
it does not even allow spaces in the path).  Change this to suit your
circumstances and security needs if running under taint mode. *Note*: you
must include the parentheses in the pattern to capture the untainted
portion of the path.

=head2 tempd

 {
     my $dir = tempd();
 }

This function is like C<pushd> but automatically creates and calls C<chdir> to
a temporary directory created by L<File::Temp>. Unlike normal L<File::Temp>
cleanup which happens at the end of the program, this temporary directory is
removed when the object is destroyed. (But also see C<preserve>.)  A warning
will be issued if the directory cannot be removed.

As with C<pushd>, C<tempd> will die if C<chdir> fails.

It may be given a single options hash that will be passed internally
to C<pushd>.

=head2 preserve

 {
     my $dir = tempd();
     $dir->preserve;      # mark to preserve at end of scope
     $dir->preserve(0);   # mark to delete at end of scope
 }

Controls whether a temporary directory will be cleaned up when the object is
destroyed.  With no arguments, C<preserve> sets the directory to be preserved.
With an argument, the directory will be preserved if the argument is true, or
marked for cleanup if the argument is false.  Only C<tempd> objects may be
marked for cleanup.  (Target directories to C<pushd> are always preserved.)
C<preserve> returns true if the directory will be preserved, and false
otherwise.

=head1 DIAGNOSTICS

C<pushd> and C<tempd> warn with message
C<"Useless use of File::pushd::I<%s> in void context"> if called in
void context and the warnings category C<void> is enabled.

  {
    use warnings 'void';

    pushd();
  }

=head1 SEE ALSO

=over 4

=item *

L<File::chdir>

=back

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/dagolden/File-pushd/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software.  The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/dagolden/File-pushd>

  git clone https://github.com/dagolden/File-pushd.git

=head1 AUTHOR

David Golden <dagolden@cpan.org>

=head1 CONTRIBUTORS

=for stopwords Diab Jerius Graham Ollis Olivier Mengué Shoichi Kaji

=over 4

=item *

Diab Jerius <djerius@cfa.harvard.edu>

=item *

Graham Ollis <plicease@cpan.org>

=item *

Olivier Mengué <dolmen@cpan.org>

=item *

Shoichi Kaji <skaji@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2018 by David A Golden.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut

__END__


# vim: ts=4 sts=4 sw=4 et:
