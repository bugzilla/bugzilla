#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::User;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($login, $action, $param, $value) = @ARGV;
($login && $action && $action =~ /^(get|set)$/)
    or die "syntax: $0 <bugzilla-login> <get|set> [param] [value]\n";

my $user = Bugzilla::User->check({ name => $login });
my $settings = $user->settings;

if ($action eq 'get') {
    if ($param eq '') {
        foreach my $name (sort keys %$settings) {
            printf "%s=%s\n", $name, $settings->{$name}->{value};
        }
    } elsif (exists $settings->{$param}) {
        say $settings->{$param}->{value};
    } else {
        die "Invalid parameter name: $param\n";
    }
} else {
    if ($param eq '') {
        die "Parameter name required\n";
    } elsif (!exists $settings->{$param}) {
        die "Invalid parameter name: $param\n";
    } elsif (!defined($value) || $value eq '') {
        die "Missing parameter value\n";
    } else {
        my $setting = $settings->{$param};
        # not using validate_value here so we can print out a list of the legal values
        my $legal_values = $setting->legal_values;
        if (! grep { $value eq $_ } @$legal_values) {
            die "Invalid value '$value' for param $param.\nAccepted values: " . join(' ', @$legal_values) . "\n";
        }
        $setting->set($value);
        say "'$param' set to '$value'";
    }
}
