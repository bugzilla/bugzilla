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
my $test_bug_2 = $config->{test_bug_2};

# Turn on usestatuswhiteboard

log_in($sel, $config, 'admin');
set_parameters($sel, {'Bug Fields' => {'usestatuswhiteboard-on' => undef}});

# Make sure the status whiteboard is displayed and add stuff to it.

go_to_bug($sel, $test_bug_1);
$sel->is_text_present_ok("Whiteboard:");
$sel->type_ok("status_whiteboard", "[msg from test_status_whiteboard.t: x77v]");
$sel->click_ok('bottom-save-btn', 'Save changes');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $test_bug_1");
go_to_bug($sel, $test_bug_2);
$sel->type_ok("status_whiteboard", "[msg from test_status_whiteboard.t: x77v]");
$sel->click_ok('bottom-save-btn', 'Save changes');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Changes submitted for bug $test_bug_2");

# Now search these bugs above using data being in the status whiteboard,
# and save the query.

open_advanced_search_page($sel);
$sel->remove_all_selections_ok("product");
$sel->remove_all_selections_ok("bug_status");
$sel->type_ok("status_whiteboard", "x77v");
$sel->click_ok("Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->is_text_present_ok("2 bugs found");
$sel->type_ok("save_newqueryname", "sw-x77v");
$sel->click_ok("remember");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search created");
my $text = trim($sel->get_text("message"));
ok($text =~ /you have a new search named sw-x77v/,
  'Saved search correctly saved');

# Make sure the saved query works.

$sel->click_ok(
  '//a[normalize-space(text())="sw-x77v" and not(@role="option")]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: sw-x77v");
$sel->is_text_present_ok("2 bugs found");

# The status whiteboard should no longer be displayed in both the query
# and bug view pages (query.cgi and show_bug.cgi) when usestatuswhiteboard
# is off.

set_parameters($sel, {'Bug Fields' => {'usestatuswhiteboard-off' => undef}});

# Show detailed bug information panel on advanced search
open_advanced_search_page($sel);
ok(!$sel->is_text_present("Whiteboard:"),
  "Whiteboard label no longer displayed");
go_to_bug($sel, $test_bug_1);
ok(!$sel->is_element_present('//label[@for="status_whiteboard"]'));

# Queries based on the status whiteboard should still work when
# the parameter is off.

$sel->click_ok('quicksearch_top');
$sel->click_ok('//a[normalize-space(text())="sw-x77v" and @role="option"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: sw-x77v");
$sel->is_text_present_ok("2 bugs found");
$sel->click_ok('forget-search');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search is gone");
$sel->is_text_present_ok("OK, the sw-x77v search is gone.");

# Turn on usestatuswhiteboard again as some other scripts may expect the status
# whiteboard to be available by default.

set_parameters($sel, {'Bug Fields' => {'usestatuswhiteboard-on' => undef}});
logout($sel);
