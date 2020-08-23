package App::cpm::Worker::Installer::Menlo;
use strict;
use warnings;

use parent 'Menlo::CLI::Compat';

use App::cpm::HTTP;
use App::cpm::Installer::Unpacker;
use App::cpm::Logger::File;
use App::cpm::Util 'WIN32';
use Command::Runner;
use Config;
use File::Which ();
use Menlo::Builder::Static;

sub new {
    my ($class, %option) = @_;
    $option{log} ||= $option{logger}->file;
    my $self = $class->SUPER::new(%option);

    if ($self->{make} = File::Which::which($Config{make})) {
        $self->{logger}->log("You have make $self->{make}");
    }
    {
        my ($http, $desc) = App::cpm::HTTP->create;
        $self->{http} = $http;
        $self->{logger}->log("You have $desc");
    }
    {
        $self->{unpacker} = App::cpm::Installer::Unpacker->new;
        my $desc = $self->{unpacker}->describe;
        for my $key (sort keys %$desc) {
            $self->{logger}->log("You have $key $desc->{$key}");
        }
    }

    $self->{initialized} = 1; # XXX

    $self;
}

sub unpack {
    my ($self, $file) = @_;
    $self->{logger}->log("Unpacking $file");
    my ($dir, $err) = $self->{unpacker}->unpack($file);
    $self->{logger}->log($err) if !$dir && $err;
    $dir;
}

sub log {
    my $self = shift;
    $self->{logger}->log(@_);
}

sub run_command {
    my ($self, $cmd) = @_;
    $self->run_timeout($cmd, 0);

}

sub run_timeout {
    my ($self, $cmd, $timeout) = @_;

    my $str = ref $cmd eq 'CODE' ? '' : ref $cmd eq 'ARRAY' ? "@$cmd" : $cmd;
    $self->{logger}->log("Executing $str") if $str;

    my $runner = Command::Runner->new(
        command => $cmd,
        keep => 0,
        redirect => 1,
        timeout => $timeout,
        stdout => sub { $self->log(@_) },
    );
    my $res = $runner->run;
    if ($res->{timeout}) {
        $self->diag_fail("Timed out (> ${timeout}s).");
        return;
    }
    my $result = $res->{result};
    ref $cmd eq 'CODE' ? $result : $result == 0;
}

1;
