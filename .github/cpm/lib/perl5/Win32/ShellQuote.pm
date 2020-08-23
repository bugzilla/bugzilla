package Win32::ShellQuote;
use strict;
use warnings FATAL => 'all';
use base 'Exporter';
use Carp;

our $VERSION = '0.003001';
$VERSION = eval $VERSION;

our @EXPORT_OK = qw(
    quote_native
    quote_cmd
    quote_system_list
    quote_system_string
    quote_system
    quote_system_cmd
    quote_literal
    cmd_escape
    unquote_native
    cmd_unescape
);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

sub quote_native {
    return join q{ }, quote_system_list(@_);
}

sub quote_cmd {
    return cmd_escape(quote_native(@_));
}

sub quote_system_list {
    # have to force quoting, or perl might try to use cmd anyway
    return map { quote_literal($_, 1) } @_;
}

sub quote_system_string {
    my $args = quote_native(@_);

    if (_has_shell_metachars($args)) {
        $args = cmd_escape($args);
    }
    return $args;
}

sub quote_system {
    if (@_ > 1) {
        return quote_system_list(@_);
    }
    else {
        return quote_system_string(@_);
    }
}

sub quote_system_cmd {
    # force cmd, even when running through system
    my $args = quote_native(@_);

    if (! _has_shell_metachars($args)) {
        # IT BURNS LOOK AWAY
        return '%PATH:~0,0%' . cmd_escape($args);
    }
    return cmd_escape($args);
}


sub cmd_escape {
    my $string = shift;
    if ($string =~ /[\r\n\0]/) {
        croak "can't quote newlines to pass through cmd.exe";
    }
    $string =~ s/([()%!^"<>&|])/^$1/g;
    return $string;
}

sub quote_literal {
    my ($text, $force) = @_;

    # basic argument quoting.  uses backslashes and quotes to escape
    # everything.
    if (!$force && $text ne '' && $text !~ /[ \t\n\x0b"]/) {
        # no quoting needed
    }
    else {
        $text =~ s{(\\*)(?="|\z)}{$1$1}g;
        $text =~ s{"}{\\"}g;
        $text = qq{"$text"};
    }

    return $text;
}

# derived from rules in code in win32.c
sub _has_shell_metachars {
    my $string = shift;

    return 1
        if $string =~ /%/;
    $string =~ s/(['"]).*?(\1|\z)//sg;
    return $string =~ /[<>|]/;
}

sub unquote_native {
    local ($_) = @_;
    my @argv;

    my $length = length
        or return @argv;

    m/\G\s*/gc;

    ARGS: until ( pos == $length ) {
        my $quote_mode;
        my $arg = '';
        CHARS: until ( pos == $length ) {
            if ( m/\G((?:\\\\)+)(?=\\?(")?)/gc ) {
                if (defined $2) {
                    $arg .= '\\' x (length($1) / 2);
                }
                else {
                    $arg .= $1;
                }
            }
            elsif ( m/\G\\"/gc ) {
                $arg .= '"';
            }
            elsif ( m/\G"/gc ) {
                if ( $quote_mode && m/\G"/gc ) {
                    $arg .= '"';
                }
                $quote_mode = !$quote_mode;
            }
            elsif ( !$quote_mode && m/\G\s+/gc ) {
                last;
            }
            elsif ( m/\G(.)/sgc ) {
                $arg .= $1;
            }
        }
        push @argv, $arg;
    }

    return @argv;
}

sub cmd_unescape {
    my ($string) = @_;

    no warnings 'uninitialized';
    $string =~ s/\^(.?)|([^^"]+)|("[^"]*(?:"|\z))/$1$2$3/gs;

    return $string;
}

1;

__END__

=head1 NAME

Win32::ShellQuote - Quote argument lists for Win32

=head1 SYNOPSIS

    use Win32::ShellQuote qw(:all);

    system quote_system('program.exe', '--switch', 'argument with spaces or other special characters');

=head1 DESCRIPTION

Quotes argument lists to be used in Win32 in several different
situations.

Windows passes its arguments as a single string instead of an array
as other platforms do.  In almost all cases, the standard Win32
L<CommandLineToArgvW|http://msdn.microsoft.com/en-us/library/ms647232.aspx>
function is used to parse this string.  F<cmd.exe> has different
rules for handling quoting, so extra work has to be done if it is
involved.  It isn't possible to consistantly create a single string
that will be handled the same by F<cmd.exe> and the stardard parsing
rules.

Perl will try to detect if you need the shell by detecting shell
metacharacters.  The routine that checks that uses different quoting
rules from both F<cmd.exe> and the native Win32 parsing.  Extra
work must therefore be done to protect against this autodetection.

=head1 SUBROUTINES

=head2 quote_native

Quotes as a string to pass directly to a program using native methods
like L<Win32::Spawn()|Win32>.  This is the safest option to use if
possible.

=head2 quote_cmd

Quotes as a string to be run through F<cmd.exe>, such as in a batch file.

=head2 quote_system_list

Quotes as a list to be passed to L<system|perlfunc/system> or
L<exec|perlfunc/exec>.  This is equally as safe as L</quote_native>,
but you must ensure you have more than one item being quoted for
the list to be usable with system.

=head2 quote_system_string

Like L</quote_system_list>, but returns a single string.  Some
argument lists cannot be properly quoted using this function.

=head2 quote_system

Switches between L</quote_system_list> and L</quote_system_string>
based on the number of items quoted.

=head2 quote_system_cmd

Quotes as a single string that will always be run with F<cmd.exe>.

=head2 quote_literal

Quotes a single parameter in native form.

=head2 cmd_escape

Escapes a string to be passed untouched by F<cmd.exe>.

=head1 CAVEATS

=over

=item *

Newlines (\n or \r) and null (\0) can't be properly quoted when
running through F<cmd.exe>.

=item *

This module re-implements some under-specified part of the perl
internals to accurately perform its work.

=back

=head1 AUTHOR

haarg - Graham Knop (cpan:HAARG) <haarg@haarg.org>

=head1 CONTRIBUTORS

=over 8

=item * Mithaldu - Christian Walde (cpan:MITHALDU) <walde.christian@googlemail.com>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2012 the L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system
itself.

=cut
