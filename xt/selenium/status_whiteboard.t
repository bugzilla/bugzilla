# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.14.0;
use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/../lib", "$RealBin/../../local/lib/perl5";

use Test::More "no_plan";

use QA::Util;

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');
set_parameters($sel, {'Bug Fields' => {'usestatuswhiteboard-on' => undef}});

# Make sure the status whiteboard is displayed and add stuff to it.

file_bug_in_product($sel, "TestProduct");
$sel->select_ok("component", "TestComponent");
my $bug_summary = "white and black";
$sel->type_ok("short_desc", $bug_summary);
$sel->type_ok("comment",    "This bug is to test the status whiteboard");
my $bug1_id = create_bug($sel, $bug_summary);
$sel->is_text_present_ok("Whiteboard:");
$sel->type_ok("status_whiteboard", "[msg from test_status_whiteboard.t: x77v]");
edit_bug($sel, $bug1_id, $bug_summary);

file_bug_in_product($sel, "TestProduct");
$sel->select_ok("component", "TestComponent");
my $bug_summary2 = "WTC";
$sel->type_ok("short_desc", $bug_summary2);
$sel->type_ok("comment",    "bugzillation!");
my $bug2_id = create_bug($sel, $bug_summary2);
$sel->type_ok("status_whiteboard", "[msg from test_status_whiteboard.t: x77v]");
edit_bug($sel, $bug2_id, $bug_summary2);

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

$sel->click_ok("link=sw-x77v");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: sw-x77v");
$sel->is_text_present_ok("2 bugs found");

# The status whiteboard should no longer be displayed in both the query
# and bug view pages (query.cgi and show_bug.cgi) when usestatuswhiteboard
# is off.

set_parameters($sel, {'Bug Fields' => {'usestatuswhiteboard-off' => undef}});
$sel->click_ok("link=Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search for bugs");
ok(!$sel->is_text_present("Whiteboard:"),
  "Whiteboard label no longer displayed in the search page");
go_to_bug($sel, $bug1_id);
ok(!$sel->is_text_present("Whiteboard:"),
  "Whiteboard label no longer displayed in the bug page");

# Queries based on the status whiteboard should still work when
# the parameter is off.

$sel->click_ok("link=sw-x77v");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: sw-x77v");
$sel->is_text_present_ok("2 bugs found");

# Turn on usestatuswhiteboard again as some other scripts may expect the status
# whiteboard to be available by default.

set_parameters($sel, {'Bug Fields' => {'usestatuswhiteboard-on' => undef}});

# Clear the status whiteboard and delete the saved search.

$sel->click_ok("link=sw-x77v");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: sw-x77v");
$sel->is_text_present_ok("2 bugs found");
$sel->click_ok("mass_change");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->click_ok("check_all");
$sel->type_ok("status_whiteboard", "");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bugs processed");

$sel->click_ok("link=sw-x77v");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: sw-x77v");
$sel->is_text_present_ok("Zarro Boogs found");
$sel->click_ok("forget_search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search is gone");
$sel->is_text_present_ok("OK, the sw-x77v search is gone.");
logout($sel);
