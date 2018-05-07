# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::SecureMail::TCT;
use 5.10.1;
use Moo;

use Bugzilla::DaemonControl qw( on_finish on_exception );
use File::Temp;
use Future::Utils qw(call);
use Future;
use IO::Async::Process;

has 'public_key'      => ( is => 'ro', required => 1 );
has 'public_key_file' => ( is => 'lazy' );
has 'is_valid'        => ( is => 'lazy' );
has 'command'         => ( is => 'ro', default  => 'tct' );

sub _build_public_key_file {
    my ($self) = @_;
    my $fh = File::Temp->new(SUFFIX => '.pubkey');
    $fh->print($self->public_key);
    $fh->close;
    return $fh;
}

sub _build_is_valid {
    my ($self) = @_;

    my $loop = IO::Async::Loop->new;
    my $exit_f = $loop->new_future;
    my ($stderr, $stdout);
    my $process = IO::Async::Process->new(
        command => [$self->command, 'check', '-k', $self->public_key_file ],
        stderr => {
            into => \$stderr,
        },
        stdout => {
            into => \$stdout,
        },
        on_finish => on_finish($exit_f),
        on_exception => on_exception($self->command, $exit_f),
    );
    $loop->add($process);

    return $exit_f->then(
        sub {
            my ($rv) = @_;
            Future->wrap($rv == 0);
        }
    );
}

sub encrypt {
    my ($self, $input, $comment) = @_;
    $self->is_valid->then(
        sub {
            my ($is_valid) = @_;
            call {
                die 'invalid public key!' unless $is_valid;

                my $output;
                my $loop = IO::Async::Loop->new;
                my $exit_f = $loop->new_future;
                my @command = ( $self->command, 'encrypt', '-k', $self->public_key_file );
                push @command, '--comment', $comment if $comment;
                my $process = IO::Async::Process->new(
                    command => \@command,
                    stdin => {
                        from => $input,
                    },
                    stdout => {
                        into => \$output,
                    },
                    on_finish => on_finish($exit_f),
                    on_exception => on_exception($self->command, $exit_f),
                );
                $loop->add($process);

                return $exit_f->then(sub { Future->wrap($output) });
            }
        }
    );
}

1;

__END__

=head1 NAME

Bugzilla::Extension::SecureMail::TCT - An interface to the tct program

=head1 SYNOPSIS

    my $key = <<'PUBLIC_KEY';
    -----BEGIN PGP PUBLIC KEY BLOCK-----

    mQINBFakJSsBEACbDwHztgZaVhIb6f4PN0KbXv5BEciqKNbdVLgWQJyqgEMIwTF7
    ...
    o858gRM=
    =t9lA
    -----END PGP PUBLIC KEY BLOCK-----
    PUBLIC_KEY

    my $tct = Bugzilla::Extension::SecureMail::TCT->new(public_key => $key);
    my $encrypted = $tct->encrypt("message", "comment goes here")->get;

