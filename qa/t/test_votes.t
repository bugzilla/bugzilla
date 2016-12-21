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

unless ($config->{test_extensions}) {
    ok(1, "this installation doesn't test extensions. Skipping test_votes.t completely.");
    exit;
}

log_in($sel, $config, 'admin');
set_parameters($sel, { "Bug Fields"              => {"useclassification-off" => undef},
                       "Administrative Policies" => {"allowbugdeletion-on"   => undef}
                     });

# Create a new product, so that we can safely play with vote settings.

add_product($sel);
$sel->type_ok("product", "Eureka");
$sel->type_ok("description", "A great new product");
$sel->type_ok("votesperuser", 10);
$sel->type_ok("maxvotesperbug", 5);
$sel->type_ok("votestoconfirm", 3);
$sel->select_ok("security_group_id", "label=core-security");
$sel->select_ok("default_op_sys_id", "Unspecified");
$sel->select_ok("default_platform_id", "Unspecified");
$sel->click_ok('//input[@type="submit" and @value="Add"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Product Created");
$sel->click_ok("link=add at least one component");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Add component to the Eureka product");
$sel->type_ok("component", "Pegasus");
$sel->type_ok("description", "A constellation in the north hemisphere.");
$sel->type_ok("initialowner", $config->{permanent_user}, "Setting the default owner");
$sel->uncheck_ok("watch_user_auto");
$sel->type_ok("watch_user", "pegasus\@eureka.bugs");
$sel->check_ok("watch_user_auto");
$sel->click_ok("create");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Component Created");
my $text = trim($sel->get_text("message"));
ok($text =~ qr/The component Pegasus has been created/, "Component 'Pegasus' created");

# Create a new bug with the CONFIRMED status.

file_bug_in_product($sel, 'Eureka');
# CONFIRMED must be the default bug status for users with editbugs privs.
$sel->selected_label_is("bug_status", "CONFIRMED");
$sel->type_ok("short_desc", "Aries");
$sel->type_ok("comment", "1st constellation");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database');
my $bug1_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# Now vote for this bug.

$sel->click_ok("link=vote");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Votes");
# No comment :-/
my $full_text = trim($sel->get_body_text());
# OK, this is not the most robust regexp, but that's better than nothing.
ok($full_text =~ /only 5 votes allowed per bug in this product/,
   "Notice about the number of votes allowed per bug displayed");
$sel->type_ok("bug_$bug1_id", 4);
$sel->click_ok("change");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Votes");
$full_text = trim($sel->get_body_text());
# OK, we may get a false positive if another product has the exact same numbers,
# but I have no better idea to check this information.
ok($full_text =~ /4 votes used out of 10 allowed/, "Display the number of votes used");

# File a new bug, now as UNCONFIRMED. We will confirm it by popular votes.

file_bug_in_product($sel, 'Eureka');
$sel->select_ok("bug_status", "UNCONFIRMED");
$sel->type_ok("short_desc", "Taurus");
$sel->type_ok("comment", "2nd constellation");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database');
my $bug2_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# Put enough votes on this bug to confirm it by popular votes.

$sel->click_ok("link=vote");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Votes");
$sel->type_ok("bug_$bug2_id", 5);
$sel->click_ok("change");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Votes");
$sel->is_text_present_ok("Bug $bug2_id confirmed by number of votes");

# File a third bug, again as UNCONFIRMED. We will confirm it
# by decreasing the number required to confirm bugs by popular votes.

file_bug_in_product($sel, 'Eureka');
$sel->select_ok("bug_status", "UNCONFIRMED");
$sel->type_ok("short_desc", "Gemini");
$sel->type_ok("comment", "3rd constellation");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database');
my $bug3_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# Vote for this bug, but remain below the threshold required
# to confirm the bug by popular votes.
# We also change votes set on other bugs for testing purposes.

$sel->click_ok("link=vote");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Votes");
$sel->type_ok("bug_$bug1_id", 2);
$sel->type_ok("bug_$bug3_id", 2);
$sel->click_ok("change");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Votes");
# Illegal change: max is 5 votes per bug!
$sel->type_ok("bug_$bug2_id", 15);
$sel->click_ok("change");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Illegal Vote");
$text = trim($sel->get_text("error_msg"));
ok($text =~ /You may only use at most 5 votes for a single bug in the Eureka product, but you are trying to use 15/,
   "Too many votes per bug");

# FIXME: We cannot use go_back_ok() here, because Firefox complains about
#        POST data not being stored in its cache. As a workaround, we go to
#        the bug we just visited and click the 'vote' link again.

go_to_bug($sel, $bug3_id);
$sel->click_ok("link=vote");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Change Votes");

# Illegal change: max is 10 votes for this product!
$sel->type_ok("bug_$bug2_id", 5);
$sel->type_ok("bug_$bug1_id", 5);
$sel->click_ok("change");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Illegal Vote");
$text = trim($sel->get_text("error_msg"));
ok($text =~ /You tried to use 12 votes in the Eureka product, which exceeds the maximum of 10 votes for this product/,
   "Too many votes for this product");

# Decrease the confirmation threshold so that $bug3 becomes confirmed.

edit_product($sel, 'Eureka');
$sel->type_ok("votestoconfirm", 2);
$sel->click_ok('//input[@type="submit" and @value="Save Changes"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Updating Product 'Eureka'");
$full_text = trim($sel->get_body_text());
ok($full_text =~ /Updated number of votes needed to confirm a bug from 3 to 2/,
   "Confirming the new number of votes to confirm");
$sel->is_text_present_ok("Bug $bug3_id confirmed by number of votes");

# Decrease the number of votes per bug so that $bug2 is updated.

$sel->click_ok("link='Eureka'");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Edit Product 'Eureka'");
$sel->type_ok("maxvotesperbug", 4);
$sel->click_ok('//input[@type="submit" and @value="Save Changes"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Updating Product 'Eureka'");
$full_text = trim($sel->get_body_text());
ok($full_text =~ /Updated maximum votes per bug from 5 to 4/, "Confirming the new number of votes per bug");
$sel->is_text_present_ok("removed votes for bug $bug2_id from " . $config->{admin_user_login}, undef,
                         "Removed votes from the admin");

# Go check that $bug2 has been correctly updated.

$sel->click_ok("link=$bug2_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/$bug2_id /);
$text = trim($sel->get_text("votes_container"));
ok($text =~ /4 votes/, "4 votes remaining");

# Decrease the number per user. Bugs should keep at least one vote,
# i.e. not all votes are removed (which was the old behavior).

edit_product($sel, "Eureka");
$sel->type_ok("votesperuser", 5);
$sel->click_ok('//input[@type="submit" and @value="Save Changes"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Updating Product 'Eureka'");
$full_text = trim($sel->get_body_text());
ok($full_text =~ /Updated votes per user from 10 to 5/, "Confirming the new number of votes per user");
$sel->is_text_present_ok("removed votes for bug");

# Go check that $bug3 has been correctly updated.

$sel->click_ok("link=$bug3_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/$bug3_id /);
$text = trim($sel->get_text("votes_container"));
ok($text =~ /2 votes/, "2 votes remaining");

# Now disable UNCONFIRMED.

edit_product($sel, "Eureka");
$sel->click_ok("allows_unconfirmed");
$sel->click_ok('//input[@type="submit" and @value="Save Changes"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Updating Product 'Eureka'");
$full_text = trim($sel->get_body_text());
ok($full_text =~ /The product no longer allows the UNCONFIRMED status/, "Disable UNCONFIRMED");

# File a new bug. UNCONFIRMED must not be listed as a valid bug status.

file_bug_in_product($sel, "Eureka");
ok(!scalar(grep {$_ eq "UNCONFIRMED"} $sel->get_select_options("bug_status")), "UNCONFIRMED not listed");
$sel->type_ok("short_desc", "Cancer");
$sel->type_ok("comment", "4th constellation");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database');
my $bug4_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# Now delete the 'Eureka' product.

go_to_admin($sel);
$sel->click_ok("link=Products");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Select product");
$sel->click_ok('//a[@href="editproducts.cgi?action=del&product=Eureka"]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Delete Product 'Eureka'");
$full_text = trim($sel->get_body_text());
ok($full_text =~ /There are 4 bugs entered for this product/, "Display warning about existing bugs");
ok($full_text =~ /Pegasus: A constellation in the north hemisphere/, "Display product description");
$sel->click_ok("delete");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Product Deleted");
logout($sel);
