package Bugzilla::Extension::MyDashboard::TimeAgo;

use strict;
use utf8;
use DateTime;
use Carp;
use Exporter qw(import);

use if $ENV{ARCH_64BIT}, 'integer';

our @EXPORT_OK = qw(time_ago);

our $VERSION = '0.06';

my @ranges = (
    [ -1, 'in the future' ],
    [ 60, 'just now' ],
    [ 900, 'a few minutes ago'], # 15*60
    [ 3000, 'less than an hour ago'], # 50*60
    [ 4500, 'about an hour ago'], # 75*60
    [ 7200, 'more than an hour ago'], # 2*60*60
    [ 21600, 'several hours ago'], # 6*60*60
    [ 86400, 'today', sub {        # 24*60*60
        my $time = shift;
        my $now = shift;
        if (   $time->day   < $now->day
            or $time->month < $now->month
            or $time->year  < $now->year
        ) {
            return 'yesterday'
        }
        if ($time->hour < 5) {
            return 'tonight'
        }
        if ($time->hour < 10) {
            return 'this morning'
        }
        if ($time->hour < 15) {
            return 'today'
        }
        if ($time->hour < 19) {
            return 'this afternoon'
        }
        return 'this evening'
    }],
    [ 172800, 'yesterday'], # 2*24*60*60
    [ 604800, 'this week'], # 7*24*60*60
    [ 1209600, 'last week'], # 2*7*24*60*60 
    [ 2678400, 'this month', sub { # 31*24*60*60
        my $time = shift;
        my $now = shift;
        if ($time->year == $now->year and $time->month == $now->month) {
            return 'this month'
        }
        return 'last month'
    }],
    [ 5356800, 'last month'], # 2*31*24*60*60
    [ 24105600, 'several months ago'], # 9*31*24*60*60
    [ 31536000, 'about a year ago'], # 365*24*60*60
    [ 34214400, 'last year'], # (365+31)*24*60*60
    [ 63072000, 'more than a year ago'], # 2*365*24*60*60
    [ 283824000, 'several years ago'], # 9*365*24*60*60
    [ 315360000, 'about a decade ago'], # 10*365*24*60*60
    [ 630720000, 'last decade'], # 20*365*24*60*60
    [ 2838240000, 'several decades ago'], # 90*365*24*60*60
    [ 3153600000, 'about a century ago'], # 100*365*24*60*60
    [ 6307200000, 'last century'], # 200*365*24*60*60
    [ 6622560000, 'more than a century ago'], # 210*365*24*60*60
    [ 28382400000, 'several centuries ago'], # 900*365*24*60*60
    [ 31536000000, 'about a millenium ago'], # 1000*365*24*60*60
    [ 63072000000, 'more than a millenium ago'], # 2000*365*24*60*60
);

sub time_ago {
    my ($time, $now) = @_;

    if (not defined $time or not $time->isa('DateTime')) {
        croak('DateTime::Duration::Fuzzy::time_ago needs a DateTime object as first parameter')
    }
    if (not defined $now) {
        $now = DateTime->now();
    }
    if (not $now->isa('DateTime')) {
        croak('Invalid second parameter provided to DateTime::Duration::Fuzzy::time_ago; it must be a DateTime object if provided')
    }

    my $now_clone = $now->clone->set_time_zone(Bugzilla->user->timezone);
    my $time_clone = $time->clone->set_time_zone(Bugzilla->user->timezone);
    my $dur = $now_clone->subtract_datetime_absolute( $time_clone )->in_units('seconds');

    foreach my $range ( @ranges ) {
        if ( $dur <= $range->[0] ) {
            if ( $range->[2] ) {
                return $range->[2]->( $time_clone, $now_clone )
            }
            return $range->[1]
        }
    }

    return 'millenia ago'
}

1

__END__

=head1 NAME

DateTime::Duration::Fuzzy -- express dates as fuzzy human-friendly strings

=head1 SYNOPSIS

 use DateTime::Duration::Fuzzy qw(time_ago);
 use DateTime;
 
 my $now = DateTime->new(
    year => 2010, month => 12, day => 12,
    hour => 19, minute => 59,
 );
 my $then = DateTime->new(
    year => 2010, month => 12, day => 12,
    hour => 15,
 );
 print time_ago($then, $now);
 # outputs 'several hours ago'
 
 print time_ago($then);
 # $now taken from C<time> function

=head1 DESCRIPTION

DateTime::Duration::Fuzzy is inspired from the timeAgo jQuery module
L<http://timeago.yarp.com/>.

It takes two DateTime objects -- first one representing a moment in the past
and second optional one representine the present, and returns a human-friendly
fuzzy expression of the time gone.

=head2 functions

=over 4

=item time_ago($then, $now)

The only exportable function.

First obligatory parameter is a DateTime object.

Second optional parameter is also a DateTime object.
If it's not provided, then I<now> as the C<time> function returns is
substituted.

Returns a string expression of the interval between the two DateTime
objects, like C<several hours ago>, C<yesterday> or <last century>.

=back

=head2 performance

On 64bit machines, it is asvisable to 'use integer', which makes
the calculations faster. You can turn this on by setting the
C<ARCH_64BIT> environmental variable to a true value.

If you do this on a 32bit machine, you will get wrong results for
intervals starting with "several decades ago".

=head1 AUTHOR

Jan Oldrich Kruza, C<< <sixtease at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Jan Oldrich Kruza.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
