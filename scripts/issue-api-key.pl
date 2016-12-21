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
use Bugzilla::User::APIKey;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $login = shift
    or die "syntax: $0 bugzilla-login [description] [api key]\n";
my $description = shift;
my $given_api_key = shift;
my $api_key;

my $user = Bugzilla::User->check({ name => $login });

my $params = {
    user_id     => $user->id,
    description => $description,
    api_key     => $given_api_key,
};

if ($description && $description eq 'mozreview') {
    $params->{app_id} = Bugzilla->params->{mozreview_app_id} // '';
}

if ($given_api_key) {
    $api_key = Bugzilla::User::APIKey->create_special($params);
} else {
    $api_key = Bugzilla::User::APIKey->create($params);
}
say $api_key->api_key;
