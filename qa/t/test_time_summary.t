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

my $test_bug_1 = $config->{test_bug_1};

# Set the timetracking group to "editbugs", which is the default value for this parameter.

log_in($sel, $config, 'admin');
set_parameters($sel, { "Group Security" => {"timetrackinggroup" => {type => "select", value => "editbugs"}} });

# Add some Hours Worked to a bug so that we are sure at least one bug
# will be present in our buglist below.

go_to_bug($sel, $test_bug_1);
$sel->type_ok("work_time", 2.6);
$sel->type_ok("comment", "I did some work");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $test_bug_1");
# Make sure the correct bug is redisplayed.
$sel->click_ok("link=bug $test_bug_1");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$test_bug_1/, "Display bug $test_bug_1");
$sel->is_text_present_ok("I did some work");
$sel->is_text_present_ok("Hours Worked: 2.6");

# Let's call summarize_time.cgi directly, with no parameters.

$sel->open_ok("/$config->{bugzilla_installation}/summarize_time.cgi");
$sel->title_is("No Bugs Selected");
my $error_msg = trim($sel->get_text("error_msg"));
ok($error_msg =~ /You apparently didn't choose any bugs to view/, "No data displayed");

# Search for bugs which have some value in the Hours Worked field.

open_advanced_search_page($sel);
$sel->remove_all_selections("bug_status");
$sel->select_ok("f1", "label=Hours Worked");
$sel->select_ok("o1", "label=is greater than");
$sel->type_ok("v1", "0");
$sel->click_ok("Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("found");

# Test dates passed to summarize_time.cgi.

$sel->click_ok("timesummary");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^Time Summary \(\d+ bugs selected\)/);
$sel->check_ok("monthly");
$sel->check_ok("detailed");
$sel->type_ok("start_date", "2009-01-01");
$sel->type_ok("end_date", "2009-04-30");
$sel->click_ok("summarize");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^Time Summary \(\d+ bugs selected\)/);
$sel->is_text_present_ok('regexp:Total of \d+\.\d+ hours worked');
$sel->is_text_present_ok("2009-01-01 to 2009-01-31");
$sel->is_text_present_ok("2009-02-01 to 2009-02-28");
$sel->is_text_present_ok("2009-04-01 to 2009-04-30");

$sel->type_ok("end_date", "2009-04-as");
$sel->click_ok("summarize");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Illegal Date");
$error_msg = trim($sel->get_text("error_msg"));
ok($error_msg =~ /'2009-04-as' is not a legal date/, "Illegal end date");

# Now display one bug only. We cannot do careful checks, because
# the page sums up contributions made by the same user during the same
# month, and so running this script several times per month would
# break checks we may want to do (e.g. by making sure that the contribution
# above has been taken into account). So we are just making sure that
# the page is displayed and throws no error.

go_to_bug($sel, $test_bug_1);
$sel->click_ok("//a[contains(text(),'Summarize time')]");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Time Summary for Bug $test_bug_1");
$sel->check_ok("inactive");
$sel->check_ok("owner");
$sel->click_ok("summarize");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Time Summary for Bug $test_bug_1");
logout($sel);
