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

# Set the querysharegroup param to be the canconfirm group.

log_in($sel, $config, 'admin');
set_parameters($sel, { "Group Security" => {"querysharegroup" => {type => "select", value => "canconfirm"}} });

# Create new saved search and call it 'Shared Selenium buglist'.

$sel->type_ok("quicksearch_top", ":TestProduct Selenium");
$sel->click_ok("find_top");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^Bug List:/);
$sel->type_ok("save_newqueryname", "Shared Selenium buglist");
$sel->click_ok("remember");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search created");
my $text = trim($sel->get_text("message"));
ok($text =~ /OK, you have a new search named Shared Selenium buglist./, "New search named 'Shared Selenium buglist' has been created");

# Retrieve the newly created saved search's internal ID and make sure it's displayed
# in the footer by default.

$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=Saved Searches");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
my $ssname = $sel->get_attribute('//input[@type="checkbox" and @alt="Shared Selenium buglist"]@name');
$ssname =~ /(?:link_in_footer_(\d+))/;
my $saved_search1_id = $1;
$sel->is_checked_ok("link_in_footer_$saved_search1_id");

# As an admin, the "Add to footer" checkbox must be displayed, but unchecked by default.

$sel->select_ok("share_$saved_search1_id", "label=canconfirm");
ok(!$sel->is_checked("force_$saved_search1_id"), "Shared search not displayed in other users' footer by default");
$sel->click_ok("force_$saved_search1_id");
$sel->click_ok("update");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
logout($sel);

# Log in as the "canconfirm" user. The search shared by the admin must appear
# in the footer.

log_in($sel, $config, 'canconfirm');
$sel->is_text_present_ok("Shared Selenium buglist");
$sel->click_ok("link=Shared Selenium buglist");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: Shared Selenium buglist");
# You cannot delete other users' saved searches.
ok(!$sel->is_text_present("Forget Search 'Shared Selenium buglist'"), "'Forget...' link not available");

# The name of the sharer must appear in the "Saved Searches" section.

$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=Saved Searches");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->is_text_present_ok($config->{admin_user_login});

# Remove the shared search from your footer.

$sel->is_checked_ok("link_in_footer_$saved_search1_id");
$sel->click_ok("link_in_footer_$saved_search1_id");
$sel->click_ok("update");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
# Go to a page where the query name is unlikely to appear in the main page.
$sel->click_ok("link=Permissions");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
ok(!$sel->is_text_present("Shared Selenium buglist"), "Shared query no longer displayed in the footer");

# Create your own saved search, and share it with the canconfirm group.

$sel->type_ok("quicksearch_top", ":TestProduct sw:helpwanted");
$sel->click_ok("find_top");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^Bug List:/);
$sel->type_ok("save_newqueryname", "helpwanted");
$sel->click_ok("remember");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search created");
$text = trim($sel->get_text("message"));
ok($text =~ /OK, you have a new search named helpwanted./, "New search named helpwanted has been created");

$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=Saved Searches");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$ssname = $sel->get_attribute('//input[@type="checkbox" and @alt="helpwanted"]@name');
$ssname =~ /(?:link_in_footer_(\d+))/;
my $saved_search2_id = $1;
# Our own saved searches are displayed in the footer by default.
$sel->is_checked_ok("link_in_footer_$saved_search2_id");
$sel->select_ok("share_$saved_search2_id", "label=canconfirm");
$sel->click_ok("update");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
logout($sel);

# Log in as admin again. The other user is not a blesser for the 'canconfirm'
# group, and so his shared search must not be displayed by default. But it
# must still be available and can be added to the footer, if desired.

log_in($sel, $config, 'admin');
ok(!$sel->is_text_present("helpwanted"), "No 'helpwanted' shared search displayed");
$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=Saved Searches");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->is_text_present_ok("helpwanted");
$sel->is_text_present_ok($config->{canconfirm_user_login});

ok(!$sel->is_checked("link_in_footer_$saved_search2_id"), "Shared query available but not displayed");
$sel->click_ok("link_in_footer_$saved_search2_id");
$sel->click_ok("update");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
# This query is now available from the footer.
$sel->click_ok("link=helpwanted");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Bug List: helpwanted");

# Remove the 'Shared Selenium buglist' query.

$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=Saved Searches");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
# There is no better way to identify the link
$sel->click_ok('//a[contains(@href,"buglist.cgi?cmdtype=dorem&remaction=forget&namedcmd=Shared%20Selenium%20buglist")]',
               undef, "Deleting the 'Shared Selenium buglist' search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search is gone");
$text = trim($sel->get_text("message"));
ok($text =~ /OK, the Shared Selenium buglist search is gone./, "The 'Shared Selenium buglist' search is gone");
logout($sel);

# Make sure that the 'helpwanted' query is not shared with the QA_Selenium_TEST
# user as he doesn't belong to the 'canconfirm' group.

log_in($sel, $config, 'QA_Selenium_TEST');
ok(!$sel->is_text_present("helpwanted"), "The 'helpwanted' query is not displayed in the footer");
$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=Saved Searches");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
ok(!$sel->is_text_present("helpwanted"), "The 'helpwanted' query is not shared with this user");
logout($sel);

# Now remove the 'helpwanted' saved search.

log_in($sel, $config, 'canconfirm');
$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
$sel->click_ok("link=Saved Searches");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("User Preferences");
ok(!$sel->is_text_present("Shared Selenium buglist"), "The 'Shared Selenium buglist' is no longer available");
$sel->click_ok('//a[contains(@href,"buglist.cgi?cmdtype=dorem&remaction=forget&namedcmd=helpwanted")]',
               undef, "Deleting the 'helpwanted' search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Search is gone");
$text = trim($sel->get_text("message"));
ok($text =~ /OK, the helpwanted search is gone./, "The 'helpwanted' search is gone");
logout($sel);
