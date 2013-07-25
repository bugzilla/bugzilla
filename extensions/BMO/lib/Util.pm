# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Util;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Extension::BMO::Data qw($cf_disabled_flags);
use Date::Parse;
use DateTime;

use base qw(Exporter);

our @EXPORT = qw( string_to_datetime
                  time_to_datetime
                  parse_date
                  is_active_status_field );

sub string_to_datetime {
    my $input = shift;
    my $time = parse_date($input)
        or ThrowUserError('report_invalid_date', { date => $input });
    return time_to_datetime($time);
}

sub time_to_datetime {
    my $time = shift;
    return DateTime->from_epoch(epoch => $time)
                   ->set_time_zone('local')
                   ->truncate(to => 'day');
}

sub parse_date {
    my ($str) = @_;
    if ($str =~ /^(-|\+)?(\d+)([hHdDwWmMyY])$/) {
        # relative date
        my ($sign, $amount, $unit, $date) = ($1, $2, lc $3, time);
        my ($sec, $min, $hour, $mday, $month, $year, $wday)  = localtime($date);
        $amount = -$amount if $sign && $sign eq '+';
        if ($unit eq 'w') {
            # convert weeks to days
            $amount = 7 * $amount + $wday;
            $unit = 'd';
        }
        if ($unit eq 'd') {
            $date -= $sec + 60 * $min + 3600 * $hour + 24 * 3600 * $amount;
            return $date;
        }
        elsif ($unit eq 'y') {
            return str2time(sprintf("%4d-01-01 00:00:00", $year + 1900 - $amount));
        }
        elsif ($unit eq 'm') {
            $month -= $amount;
            while ($month < 0) { $year--; $month += 12; }
            return str2time(sprintf("%4d-%02d-01 00:00:00", $year + 1900, $month + 1));
        }
        elsif ($unit eq 'h') {
            # Special case 0h for 'beginning of this hour'
            if ($amount == 0) {
                $date -= $sec + 60 * $min;
            } else {
                $date -= 3600 * $amount;
            }
            return $date;
        }
        return undef;
    }
    return str2time($str);
}

sub is_active_status_field {
    my ($field) = @_;
    if ($field->type != FIELD_TYPE_EXTENSION
        && $field->name =~ /^cf_status/)
    {
        return !grep { $field->name eq $_ } @$cf_disabled_flags
    }

    if ($field->type == FIELD_TYPE_EXTENSION
        && $field->can('flag_type')
        && $field->flag_type eq 'status')
    {
        return 1;
    }

    return 0;
}

1;
