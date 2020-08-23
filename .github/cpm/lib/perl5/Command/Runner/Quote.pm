package Command::Runner::Quote;
use strict;
use warnings;

use Win32::ShellQuote ();
use String::ShellQuote ();

use Exporter 'import';
our @EXPORT_OK = qw(quote quote_win32 quote_unix);

sub quote_win32 {
    my $str = shift;
    Win32::ShellQuote::quote_literal($str, 1);
}

sub quote_unix {
    my $str = shift;
    String::ShellQuote::shell_quote_best_effort($str);
}

if ($^O eq 'MSWin32') {
    *quote = \&quote_win32;
} else {
    *quote = \&quote_unix;
}

1;
