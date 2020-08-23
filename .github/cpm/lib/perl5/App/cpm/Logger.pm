package App::cpm::Logger;
use strict;
use warnings;

use App::cpm::Util 'WIN32';
use List::Util 'max';

our $COLOR;
our $VERBOSE;
our $SHOW_PROGRESS;

my %color = (
    resolve => 33,
    fetch => 34,
    configure => 35,
    install => 36,
    FAIL => 31,
    DONE => 32,
    WARN => 33,
);

our $HAS_WIN32_COLOR;

sub new {
    my $class = shift;
    bless {@_}, $class;
}

sub log {
    my ($self, %option) = @_;
    my $type = $option{type} || "";
    my $message = $option{message};
    chomp $message;
    my $optional = $option{optional} ? " ($option{optional})" : "";
    my $result = $option{result};
    my $is_color = ref $self ? $self->{color} : $COLOR;
    my $verbose = ref $self ? $self->{verbose} : $VERBOSE;
    my $show_progress = ref $self ? $self->{show_progress} : $SHOW_PROGRESS;

    if ($is_color and WIN32) {
        if (!defined $HAS_WIN32_COLOR) {
            $HAS_WIN32_COLOR = eval { require Win32::Console::ANSI; 1 } ? 1 : 0;
        }
        $is_color = 0 unless $HAS_WIN32_COLOR;
    }

    if ($is_color) {
        $type = "\e[$color{$type}m$type\e[m" if $type && $color{$type};
        $result = "\e[$color{$result}m$result\e[m" if $result && $color{$result};
        $optional = "\e[1;37m$optional\e[m" if $optional;
    }

    my $r = $show_progress ? "\r" : "";
    if ($verbose) {
        # type -> 5 + 9 + 3
        $type = $is_color && $type ? sprintf("%-17s", $type) : sprintf("%-9s", $type || "");
        warn $r . sprintf "%d %s %s %s%s\n", $option{pid} || $$, $result, $type, $message, $optional;
    } else {
        warn $r . join(" ", $result, $type ? $type : (), $message . $optional) . "\n";
    }
}

1;
