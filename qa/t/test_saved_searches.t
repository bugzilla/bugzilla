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

# If a saved search named 'SavedSearchTEST1' exists, remove it.

log_in($sel, $config, 'QA_Selenium_TEST');
$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=Saved Searches");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");

if($sel->is_text_present("SavedSearchTEST1")) {
    # There is no other way to identify this link (as they are all named "Forget").
    $sel->click_ok('//a[contains(@href,"buglist.cgi?cmdtype=dorem&remaction=forget&namedcmd=SavedSearchTEST1")]');
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Search is gone");
    $sel->is_text_present_ok("OK, the SavedSearchTEST1 search is gone.");
}

# Create a new saved search.

open_advanced_search_page($sel);
$sel->type_ok("short_desc", "test search");
$sel->click_ok("Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
$sel->type_ok("save_newqueryname", "SavedSearchTEST1");
$sel->click_ok("remember");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search created");
my $text = trim($sel->get_text("message"));
ok($text =~ /OK, you have a new search named SavedSearchTEST1./, "New search named SavedSearchTEST1 has been created");
$sel->click_ok("link=SavedSearchTEST1");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: SavedSearchTEST1");

# Remove the saved search from the page footer. It should no longer be displayed there.

$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=Saved Searches");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");

$sel->is_text_present_ok("SavedSearchTEST1");
$sel->uncheck_ok('//input[@type="checkbox" and @alt="SavedSearchTEST1"]');
# $sel->value_is("//input[\@type='checkbox' and \@alt='SavedSearchTEST1']", "off");
$sel->click_ok("update");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$text = trim($sel->get_text("message"));
ok($text =~ /The changes to your saved searches have been saved./, "Saved searches changes have been saved");

# Modify the saved search. Said otherwise, we should still be able to save
# a new search with exactly the same name.

open_advanced_search_page($sel);
$sel->type_ok("short_desc", "bilboa");
$sel->click_ok("Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List");
# As we said, this saved search should no longer be displayed in the page footer.
ok(!$sel->is_text_present("SavedSearchTEST1"), "SavedSearchTEST1 is not present in the page footer");
$sel->type_ok("save_newqueryname", "SavedSearchTEST1");
$sel->click_ok("remember");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search updated");
$text = trim($sel->get_text("message"));
ok($text =~ /Your search named SavedSearchTEST1 has been updated./, "Saved searche SavedSearchTEST1 has been updated.");

# Make sure our new criteria has been saved (let's edit the saved search).
# As the saved search is no longer displayed in the footer, we have to go
# to the "Preferences" page to edit it.

$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=Saved Searches");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");

$sel->is_text_present_ok("SavedSearchTEST1");
$sel->click_ok('//a[@href="buglist.cgi?cmdtype=dorem&remaction=run&namedcmd=SavedSearchTEST1"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: SavedSearchTEST1");
$sel->click_ok("link=Edit Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search for bugs");
$sel->value_is("short_desc", "bilboa");
$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->click_ok("link=Forget Search 'SavedSearchTEST1'");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search is gone");
$text = trim($sel->get_text("message"));
ok($text =~ /OK, the SavedSearchTEST1 search is gone./, "The SavedSearchTEST1 search is gone.");
logout($sel);
