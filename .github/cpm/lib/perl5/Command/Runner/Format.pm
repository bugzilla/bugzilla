package Command::Runner::Format;
use strict;
use warnings;

use Command::Runner::Quote 'quote';

use Exporter 'import';
our @EXPORT_OK = qw(commandf);

# taken from String::Format
my $regex = qr/
               (%             # leading '%'                    $1
                (-)?          # left-align, rather than right  $2
                (\d*)?        # (optional) minimum field width $3
                (?:\.(\d*))?  # (optional) maximum field width $4
                (\{.*?\})?    # (optional) stuff inside        $5
                (\S)          # actual format character        $6
             )/x;

sub commandf {
    my ($format, @args) = @_;
    my $i = 0;
    $format =~ s{$regex}{
        $6 eq '%' ? '%' : _replace($args[$i++], $1, $6)
    }ge;
    $format;
}

sub _replace {
    my ($arg, $all, $char) = @_;
    if ($char eq 'q') {
        return quote $arg;
    } else {
        return sprintf $all, $arg;
    }
}

1;
