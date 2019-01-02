#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.10.1;
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );
use Test::More;
use Test2::Tools::Mock qw(mock);
use Bugzilla::Test::MockParams (
  phabricator_auth_callback_url => 'http://pants.gov/',);

is(Bugzilla->params->{phabricator_auth_callback_url},
  'http://pants.gov/', 'import default params');

Bugzilla::Test::MockParams->import(phabricator_api_key => 'FAKE-KEY');

is(Bugzilla->params->{phabricator_api_key}, 'FAKE-KEY', 'set key');


done_testing;
