package Command::Runner;
use strict;
use warnings;

use Capture::Tiny ();
use Command::Runner::Format ();
use Command::Runner::LineBuffer;
use Command::Runner::Quote ();
use Config ();
use IO::Select;
use POSIX ();
use Time::HiRes ();

use constant WIN32 => $^O eq 'MSWin32';

our $VERSION = '0.102';
our $TICK = 0.02;

sub new {
    my ($class, %option) = @_;
    my $command = delete $option{command};
    my $commandf = delete $option{commandf};
    die "Cannot specify both command and commandf" if $command && $commandf;
    if (!$command && $commandf) {
        $command = Command::Runner::Format::commandf @$commandf;
    }
    bless {
        keep => 1,
        _buffer => {},
        %option,
        ($command ? (command => $command) : ()),
    }, $class;
}

for my $attr (qw(command redirect timeout keep stdout stderr env)) {
    no strict 'refs';
    *$attr = sub {
        my $self = shift;
        $self->{$attr} = $_[0];
        $self;
    };
}

sub commandf {
    my ($self, $format, @args) = @_;
    $self->{command} = Command::Runner::Format::commandf $format, @args;
    $self;
}

sub run {
    my $self = shift;
    local %ENV = %{$self->{env}} if $self->{env};
    my $command = $self->{command};
    if (ref $command eq 'CODE') {
        $self->_wrap(sub { $self->_run_code($command) });
    } elsif (WIN32) {
        $self->_wrap(sub { $self->_system_win32($command) });
    } else {
        $self->_exec($command);
    }
}

sub _wrap {
    my ($self, $code) = @_;

    my ($stdout, $stderr, $res);
    if ($self->{redirect}) {
        ($stdout, $res) = &Capture::Tiny::capture_merged($code);
    } else {
        ($stdout, $stderr, $res) = &Capture::Tiny::capture($code);
    }

    if (length $stdout and my $sub = $self->{stdout}) {
        my $buffer = Command::Runner::LineBuffer->new(buffer => $stdout);
        my @line = $buffer->get(1);
        $sub->($_) for @line;
    }
    if (!$self->{redirect} and length $stderr and my $sub = $self->{stderr}) {
        my $buffer = Command::Runner::LineBuffer->new(buffer => $stderr);
        my @line = $buffer->get(1);
        $sub->($_) for @line;
    }

    if ($self->{keep}) {
        $res->{stdout} = $stdout;
        $res->{stderr} = $stderr;
    }

    return $res;
}

sub _run_code {
    my ($self, $code) = @_;

    if (!$self->{timeout}) {
        my $result = $code->();
        return { pid => $$, result => $result };
    }

    my ($result, $err);
    {
        local $SIG{__DIE__} = 'DEFAULT';
        local $SIG{ALRM} = sub { die "__TIMEOUT__\n" };
        eval {
            alarm $self->{timeout};
            $result = $code->();
        };
        $err = $@;
        alarm 0;
    }
    if (!$err) {
        return { pid => $$, result => $result, };
    } elsif ($err eq "__TIMEOUT__\n") {
        return { pid => $$, result => $result, timeout => 1 };
    } else {
        die $err;
    }
}

sub _system_win32 {
    my ($self, $command) = @_;

    my $pid;
    if (ref $command) {
        my @cmd = map { Command::Runner::Quote::quote_win32($_) } @$command;
        $pid = system { $command->[0] } 1, @cmd;
    } else {
        $pid = system 1, $command;
    }

    my $timeout_at = $self->{timeout} ? Time::HiRes::time() + $self->{timeout} : undef;
    my $INT; local $SIG{INT} = sub { $INT++ };
    my ($result, $timeout);
    while (1) {
        if ($INT) {
            kill INT => $pid;
            $INT = 0;
        }

        my $res = waitpid $pid, POSIX::WNOHANG();
        if ($res == -1) {
            warn "waitpid($pid, POSIX::WNOHANG()) returns unexpectedly -1";
            last;
        } elsif ($res > 0) {
            $result = $?;
            last;
        } else {
            if ($timeout_at) {
                my $now = Time::HiRes::time();
                if ($timeout_at <= $now) {
                    $timeout = 1;
                    kill TERM => $pid;
                }
            }
            Time::HiRes::sleep($TICK);
        }
    }
    return { pid => $pid, result => $result, timeout => $timeout };
}

sub _exec {
    my ($self, $command) = @_;

    pipe my $stdout_read, my $stdout_write;
    $self->{_buffer}{stdout} = Command::Runner::LineBuffer->new(keep => $self->{keep});

    my ($stderr_read, $stderr_write);
    if (!$self->{redirect}) {
        pipe $stderr_read, $stderr_write;
        $self->{_buffer}{stderr} = Command::Runner::LineBuffer->new(keep => $self->{keep});
    }

    my $pid = fork;
    die "fork: $!" unless defined $pid;
    if ($pid == 0) {
        close $_ for grep $_, $stdout_read, $stderr_read;
        open STDOUT, ">&", $stdout_write;
        if ($self->{redirect}) {
            open STDERR, ">&", \*STDOUT;
        } else {
            open STDERR, ">&", $stderr_write;
        }
        if ($Config::Config{d_setpgrp}) {
            POSIX::setpgid(0, 0) or die "setpgid: $!";
        }

        if (ref $command) {
            exec { $command->[0] } @$command;
        } else {
            exec $command;
        }
        exit 127;
    }
    close $_ for grep $_, $stdout_write, $stderr_write;

    my $signal_pid = $Config::Config{d_setpgrp} ? -$pid : $pid;

    my $INT; local $SIG{INT} = sub { $INT++ };
    my $timeout;
    my $timeout_at = $self->{timeout} ? Time::HiRes::time() + $self->{timeout} : undef;
    my $select = IO::Select->new(grep $_, $stdout_read, $stderr_read);

    while ($select->count) {
        if ($INT) {
            kill INT => $signal_pid;
            $INT = 0;
        }
        if ($timeout_at and !$timeout) {
            my $now = Time::HiRes::time();
            if ($now > $timeout_at) {
                $timeout++;
                kill TERM => $signal_pid;
            }
        }

        for my $ready ($select->can_read($TICK)) {
            my $type = $ready == $stdout_read ? "stdout" : "stderr";
            my $len = sysread $ready, my $buf, 64*1024;
            if ($len) {
                my $buffer = $self->{_buffer}{$type};
                $buffer->add($buf);
                next unless my @line = $buffer->get;
                next unless my $sub = $self->{$type};
                $sub->($_) for @line;
            } else {
                warn "sysread $type pipe failed: $!" unless defined $len;
                $select->remove($ready);
                close $ready;
            }
        }
    }
    for my $type (qw(stdout stderr)) {
        next unless my $sub = $self->{$type};
        my $buffer = $self->{_buffer}{$type} or next;
        my @line = $buffer->get(1) or next;
        $sub->($_) for @line;
    }
    close $_ for $select->handles;
    waitpid $pid, 0;
    my $res = {
        pid => $pid,
        result => $?,
        timeout => $timeout,
        stdout => $self->{_buffer}{stdout} ? $self->{_buffer}{stdout}->raw : "",
        stderr => $self->{_buffer}{stderr} ? $self->{_buffer}{stderr}->raw : "",
    };
    $self->{_buffer} = +{}; # cleanup
    return $res;
}

1;
__END__

=encoding utf-8

=head1 NAME

Command::Runner - run external commands and Perl code refs

=head1 SYNOPSIS

  use Command::Runner;

  my $cmd = Command::Runner->new(
    command => ['ls', '-al'],
    timeout => 10,
    stdout  => sub { warn "out: $_[0]\n" },
    stderr  => sub { warn "err: $_[0]\n" },
  );
  my $res = $cmd->run;

  my $untar = Command::Runner->new;
  $untar->commandf(
    '%q -dc %q | %q tf -',
    'C:\\Program Files (x86)\\GnuWin32\\bin\\gzip.EXE',
    'File-ShareDir-Install-0.13.tar.gz'
    'C:\\Program Files (x86)\\GnuWin32\\bin\\tar.EXE',
  );
  my $capture = $untar->run->{stdout};

=head1 DESCRIPTION

Command::Runner runs external commands and Perl code refs

=head1 METHODS

=head2 new

A constructor, which takes:

=over 4

=item command

an array of external commands, a string of external programs, or a Perl code ref.
If an array of external commands is specified, it is automatically quoted on Windows.

=item commandf

a command string by C<sprintf>-like syntax.
You can use positional formatting together with a conversion C<%q> (with quoting).

Here is an example:

  my $cmd = Command::Runner->new(
    commandf => [ '%q %q >> %q', '/path/to/cat', 'foo bar.txt', 'out.txt' ],
  );

  # or, you can set it separately
  my $cmd = Command::Runner->new;
  $cmd->commandf('%q %q >> %q', '/path/to/cat', 'foo bar.txt', 'out.txt');

=item timeout

timeout second. You can set float second.

=item redirect

if this is true, stderr redirects to stdout

=item keep

by default, even if stdout/stderr is consumed, it is preserved for return value.
You can disable this behavior by setting keep option false.

=item stdout / stderr

a code ref that will be called whenever stdout/stderr is available

=item env

set environment variables.

  Command::Runner->new(..., env => \%env)->run

is equivalent to

  {
    local %ENV = %env;
    Command::Runner->new(...)->run;
  }

=back

=head2 run

Run command. It returns a hash reference, which contains:

=over 4

=item result

=item timeout

=item stdout

=item stderr

=item pid

=back

=head1 MOTIVATION

I develop a CPAN client L<App::cpm>, where I need to execute external commands and Perl code refs with:

=over 4

=item timeout

=item quoting

=item flexible logging

=back

While L<App::cpanminus> has excellent APIs for such use, I still needed to tweak them in L<App::cpm>.

So I ended up creating a seperate module, Command::Runner.

=head1 AUTHOR

Shoichi Kaji <skaji@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2017 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
