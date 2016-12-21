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

# Very simple test script to test if bug creation with minimal data
# passes successfully for different user privileges.
#
# More elaborate tests exist in other scripts. This doesn't mean this
# one could not be improved a bit.

foreach my $user (qw(admin unprivileged canconfirm)) {
    log_in($sel, $config, $user);
    file_bug_in_product($sel, "TestProduct");
    $sel->type_ok("short_desc", "Bug created by Selenium",
                  "Enter bug summary");
    $sel->type_ok("comment", "--- Bug created by Selenium ---",
                  "Enter bug description");
    $sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->is_text_present_ok('has been added to the database', 'Bug created');
    logout($sel);
}
