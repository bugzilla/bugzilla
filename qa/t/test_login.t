# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More "no_plan";

use QA::Util;

my ($sel, $config) = get_selenium();

# FIXME: At some point, this trivial script should be merged with test_create_user_accounts.t.
#        Either that or we should improve this script a lot.

# Try to log in to Bugzilla using an invalid account. To be sure that the login form
# is triggered, we try to access an admin page.

$sel->open_ok("/$config->{bugzilla_installation}/editparams.cgi");
$sel->title_is("Log in to Bugzilla");
# The login and password are hardcoded here, because this account doesn't exist.
$sel->type_ok("Bugzilla_login", 'guest@foo.com');
$sel->type_ok("Bugzilla_password", 'foo-bar-baz');
$sel->click_ok("log_in");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Invalid Username Or Password");
$sel->is_text_present_ok("The username or password you entered is not valid.");
