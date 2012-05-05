# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::Server;
use strict;

use Bugzilla::Error;
use Bugzilla::Util qw(datetime_from);

use Scalar::Util qw(blessed);

sub handle_login {
    my ($self, $class, $method, $full_method) = @_;
    eval "require $class";
    ThrowCodeError('unknown_method', {method => $full_method}) if $@;
    return if ($class->login_exempt($method) 
               and !defined Bugzilla->input_params->{Bugzilla_login});
    Bugzilla->login();
}

sub datetime_format_inbound {
    my ($self, $time) = @_;
    
    my $converted = datetime_from($time, Bugzilla->local_timezone);
    if (!defined $converted) {
        ThrowUserError('illegal_date', { date => $time });
    }
    $time = $converted->ymd() . ' ' . $converted->hms();
    return $time
}

sub datetime_format_outbound {
    my ($self, $date) = @_;

    return undef if (!defined $date or $date eq '');

    my $time = $date;
    if (blessed($date)) {
        # We expect this to mean we were sent a datetime object
        $time->set_time_zone('UTC');
    } else {
        # We always send our time in UTC, for consistency.
        # passed in value is likely a string, create a datetime object
        $time = datetime_from($date, 'UTC');
    }
    return $time->iso8601();
}

1;
