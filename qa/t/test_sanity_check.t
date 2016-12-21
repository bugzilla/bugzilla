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

log_in($sel, $config, 'admin');
go_to_admin($sel);
$sel->click_ok("link=Sanity Check", undef, "Go to Sanity Check (no parameter)");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Sanity Check", "Display sanitycheck.cgi");
$sel->is_text_present_ok("Sanity check completed.", undef, "Page displayed correctly");

my @args = qw(rebuildvotecache createmissinggroupcontrolmapentries repair_creation_date
              repair_bugs_fulltext remove_invalid_bug_references repair_bugs_fulltext
              remove_invalid_attach_references remove_old_whine_targets rescanallBugMail);

foreach my $arg (@args) {
    $sel->open_ok("/$config->{bugzilla_installation}/sanitycheck.cgi?$arg=1");
    $sel->title_is("Suspicious Action", "Calling sanitycheck.cgi with no token triggers a confirmation page");
    $sel->click_ok("confirm", "Confirm the action");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Sanity Check", "Calling sanitycheck.cgi with $arg=1");
    if ($arg eq 'rescanallBugMail') {
        # sanitycheck.cgi always stops after looking for unsent bugmail. So we cannot rely on
        # "Sanity check completed." to determine if an error has been thrown or not.
        $sel->is_text_present_ok("found with possibly unsent mail", undef, "Look for unsent bugmail");
        ok(!$sel->is_text_present("Software error"), "No error thrown");
    }
    else {
        $sel->is_text_present_ok("Sanity check completed.", undef, "Page displayed correctly");
    }
}

logout($sel);
