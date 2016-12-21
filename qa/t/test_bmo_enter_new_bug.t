# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Comments:
# 1. Some of the forms have been commented as they have been removed since
#    this script was originally created. I left them in insteading of deleting
#    so they could be used for reference for adding new form tests.
# 2. The _check_* utility functions for creating objects should be moved to
#    generate_test_data.pl at some point.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More "no_plan";

use QA::Util;

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');
set_parameters($sel, { "Bug Fields" => {"useclassification-off" => undef} });

# mktgevent and swag are dependent so we create the mktgevent bug first so
# we can provide the bug id to swag

## mktgevent
#
#_check_product('Marketing');
#_check_component('Marketing', 'Event Requests');
#_check_component('Marketing', 'Swag Requests');
#_check_group('mozilla-corporation-confidential');
#
## FIXME figure out how to use format= with file_bug_in_product
#
#$sel->open_ok("/$config->{bugzilla_installation}/enter_bug.cgi?product=Marketing&format=mktgevent");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->title_is("Event Request Form", "Open custom bug entry form - mktgevent");
#$sel->type_ok("firstname", "Bugzilla", "Enter first name");
#$sel->type_ok("lastname", "Administrator", "Enter last name");
#$sel->type_ok("email", $config->{'admin_user_login'}, "Enter email address");
#$sel->type_ok("eventname", "Event Name", "Enter event name");
#$sel->type_ok("website", $config->{'browser_url'}, "Enter web site");
#$sel->type_ok("goals", "Goals for the event", "Enter goals");
#$sel->type_ok("date", "2032/01/01", "Enter date");
#$sel->type_ok("successmeasure", "Success Measure", "Enter measure of success");
#$sel->click_ok("doing", "value=Other", "Select what doing");
#$sel->type_ok("doing-other-what", "What will you be doing at the event", "Enter other what doing");
#$sel->select_ok("attendees", "value=1-99", "Select number of attendees");
#$sel->select_ok("audience", "value=Contributors", "Select targeted audience");
#$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->is_text_present_ok('has been added to the database', 'Bug created');
#my $mktgevent_bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');
#
## swag
#
#$sel->open_ok("/$config->{bugzilla_installation}/enter_bug.cgi?product=Marketing&format=swag");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->title_is("Swag Request Form", "Open custom bug entry form - swag");
#$sel->type_ok("firstname", "Bugzilla", "Enter first name");
#$sel->type_ok("lastname", "Administrator", "Enter last name");
#$sel->type_ok("dependson", $mktgevent_bug_id, "Enter event request bug id");
#$sel->type_ok("email", $config->{'admin_user_login'}, "Enter email address");
#$sel->type_ok("cc", $config->{'unprivileged_user_login'}, "Enter cc address");
#$sel->type_ok("additional", "Specific swag needed", "Enter specific swag needed");
#$sel->type_ok("shiptofirstname", "Bugzilla", "Enter ship to first name");
#$sel->type_ok("shiptolastname", "Administrator", "Enter ship to last name");
#$sel->type_ok("shiptoaddress", "100 Some Street", "Enter ship to address");
#$sel->type_ok("shiptoaddress2", "Suite 200", "Enter ship to address 2");
#$sel->type_ok("shiptocity", "Mountain View", "Enter ship to city");
#$sel->type_ok("shiptostate", "California", "Enter ship to state");
#$sel->type_ok("shiptocountry", "USA", "Enter ship to country");
#$sel->type_ok("shiptopcode", "94041", "Enter ship to postal code");
#$sel->type_ok("shiptophone", "1-800-555-1212", "Enter ship to phone");
#$sel->type_ok("shiptoidrut", "What is this?", "Enter ship to personal id/rut");
#$sel->type_ok("comment", "--- Bug created by Selenium ---", "Enter bug description");
#$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->is_text_present_ok('has been added to the database', 'Bug created');
#my $swag_bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# trademark

_check_product('Marketing');
_check_component('Marketing', 'Trademark Permissions');
_check_group('marketing-private');

$sel->open_ok("/$config->{bugzilla_installation}/enter_bug.cgi?product=Marketing&format=trademark");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Trademark Usage Requests", "Open custom bug entry form - trademark");
$sel->type_ok("short_desc", "Bug created by Selenium", "Enter bug summary");
$sel->type_ok("comment", "--- Bug created by Selenium ---", "Enter bug description");
$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
my $trademark_bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# itrequest

_check_product('mozilla.org');
_check_product('Infrastructure & Operations');
_check_component('Infrastructure & Operations', 'WebOps: Other');
_check_version('Infrastructure & Operations', 'other');
_check_group('infra');

#$sel->open_ok("/$config->{bugzilla_installation}/enter_bug.cgi?product=mozilla.org&format=itrequest");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->title_is("Mozilla Corporation/Foundation IT Requests", "Open custom bug entry form - itrequest");
#$sel->click_ok("component_webops_other", "Select request type");
#$sel->type_ok("cc", $config->{'unprivileged_user_login'}, "Enter cc address");
#$sel->type_ok("short_desc", "Bug created by Selenium", "Enter request summary");
#$sel->type_ok("comment", "--- Bug created by Selenium ---", "Enter request description");
#$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->is_text_present_ok('has been added to the database', 'Bug created');
#my $itrequest_bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# brownbag

#$sel->open_ok("/$config->{bugzilla_installation}/enter_bug.cgi?product=mozilla.org&format=brownbag");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->title_is("Mozilla Corporation Brownbag Requests", "Open custom bug entry form - brownbag");
#$sel->type_ok("presenter", "Bugzilla Administrator", "Enter presenter");
#$sel->type_ok("topic", "Automated testing of Bugzilla", "Enter topic");
#$sel->type_ok("date", "01/01/2012", "Enter date");
#$sel->select_ok("time_hour", "value=1", "Select hour");
#$sel->select_ok("time_minute", "value=30", "Select minute");
#$sel->select_ok("ampm", "value=PM", "Select am/pm");
#$sel->select_ok("audience", "value=Employees Only", "Select audience");
#$sel->check_ok("airmozilla", "Select need airmozilla");
#$sel->check_ok("dialin", "Select need dial in");
#$sel->check_ok("archive", "Select need to be archived");
#$sel->check_ok("ithelp", "Select need it help");
#$sel->type_ok("cc", $config->{'unprivileged_user_login'}, "Enter cc address");
#$sel->type_ok("description", "--- Bug created by Selenium ---", "Enter request description");
#$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->is_text_present_ok('has been added to the database', 'Bug created');
#my $brownbag_bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# presentation

#$sel->open_ok("/$config->{bugzilla_installation}/enter_bug.cgi?product=mozilla.org&format=presentation");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->title_is("Mozilla Corporation Mountain View Presentation Request", "Open custom bug entry form - presentation");
#$sel->type_ok("presenter", "Bugzilla Administrator", "Enter presenter");
#$sel->type_ok("topic", "Automated testing of Bugzilla", "Enter topic");
#$sel->type_ok("date", "01/01/2012", "Enter date");
#$sel->select_ok("time_hour", "value=1", "Select hour");
#$sel->select_ok("time_minute", "value=30", "Select minute");
#$sel->select_ok("ampm", "value=PM", "Select am/pm");
#$sel->select_ok("audience", "value=Employees Only", "Select audience");
#$sel->check_ok("airmozilla", "Select need airmozilla");
#$sel->check_ok("dialin", "Select need dial in");
#$sel->check_ok("archive", "Select need to be archived");
#$sel->check_ok("ithelp", "Select need it help");
#$sel->type_ok("cc", $config->{'unprivileged_user_login'}, "Enter cc address");
#$sel->type_ok("description", "--- Bug created by Selenium ---", "Enter request description");
#$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->is_text_present_ok('has been added to the database', 'Bug created');
#my $presentation_bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

_check_component('mozilla.org', 'Discussion Forums');

#mozlist

_check_version('mozilla.org', 'other');
_check_component('mozilla.org', 'Discussion Forums');

$sel->open_ok("/$config->{bugzilla_installation}/enter_bug.cgi?product=mozilla.org&format=mozlist");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Mozilla Discussion Forum", "Open custom bug entry form - mozlist");
$sel->type_ok("listName", "test-list", "Enter name for mailing list");
$sel->type_ok("listAdmin", $config->{'admin_user_login'}, "Enter list administator");
$sel->type_ok("cc", $config->{'unprivileged_user_login'}, "Enter cc address");
$sel->check_ok("name=groups", "value=infra", "Select private group");
$sel->type_ok("comment", "--- Bug created by Selenium ---", "Enter bug description");
$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
my $mozlist_bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

_check_product('Mozilla PR');
_check_component('Mozilla PR', 'China - AMO');
_check_group('mozilla-confidential');

#mozpr

_check_group('pr-private');

#$sel->open_ok("/$config->{bugzilla_installation}/enter_bug.cgi?product=Mozilla PR&format=mozpr");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->title_is("Create a PR Request", "Open custom bug entry form - mozpr");
#$sel->select_ok("location", "value=China", "Select location");
#$sel->select_ok("component", "value=China - AMO", "Select component");
#$sel->select_ok("fakecomp", "value=AMO", "Select fake component");
#$sel->type_ok("cc", $config->{'unprivileged_user_login'}, "Enter cc address");
#$sel->type_ok("short_desc", "Bug created by Selenium", "Enter bug summary");
#$sel->type_ok("comment", "--- Bug created by Selenium ---", "Enter bug description");
#$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
#$sel->wait_for_page_to_load_ok(WAIT_TIME);
#$sel->is_text_present_ok('has been added to the database', 'Bug created');
#my $mozpr_bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# legal

_check_product('Legal');
_check_component('Legal', 'Contract Request');
_check_group('mozilla-employee-confidential'); 

$sel->open_ok("/$config->{bugzilla_installation}/enter_bug.cgi?product=Legal&format=legal");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Mozilla Corporation Legal Requests", "Open custom bug entry form - legal");
$sel->select_ok("component", "value=Contract Request", "Select request type");
$sel->select_ok("business_unit", "value=Connected Devices", "Select business unit");
$sel->type_ok("short_desc", "Bug created by Selenium", "Enter request summary");
$sel->type_ok("cc", $config->{'unprivileged_user_login'}, "Enter cc address");
$sel->type_ok("important_dates", "Important dates", "Enter important dates");
$sel->type_ok("comment", "--- Bug created by Selenium ---", "Enter request description");
$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
my $legal_bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

# poweredby

_check_product('Websites', 'other');
_check_component('Websites', 'www.mozilla.org');
_check_user('liz@mozilla.com');

$sel->open_ok("/$config->{bugzilla_installation}/enter_bug.cgi?product=Websites&format=poweredby");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Powered by Mozilla Logo Requests", "Open custom bug entry form - poweredby");
$sel->type_ok("short_desc", "Bug created by Selenium", "Enter bug summary");
$sel->type_ok("comment", "--- Bug created by Selenium ---", "Enter bug description");
$sel->click_ok("commit", undef, "Submit bug data to post_bug.cgi");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok('has been added to the database', 'Bug created');
my $poweredby_bug_id = $sel->get_value('//input[@name="id" and @type="hidden"]');

set_parameters($sel, { "Bug Fields" => {"useclassification-on" => undef} });
logout($sel);

sub _check_product {
    my ($product, $version) = @_;

    go_to_admin($sel);
    $sel->click_ok("link=Products");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Select product");

    my $product_description = "$product Description";

    my $text = trim($sel->get_text("bugzilla-body"));
    if ($text =~ /$product_description/) {
        # Product exists already
        return 1;
    }

    $sel->click_ok("link=Add");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Add Product");
    $sel->type_ok("product", $product);
    $sel->type_ok("description", $product_description);
    $sel->type_ok("version", $version) if $version;
    $sel->select_ok("security_group_id", "label=core-security");
    $sel->select_ok("default_op_sys_id", "Unspecified");
    $sel->select_ok("default_platform_id", "Unspecified");
    $sel->click_ok('//input[@type="submit" and @value="Add"]');
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $text = trim($sel->get_text("message"));
    ok($text =~ /You will need to add at least one component before anyone can enter bugs against this product/,
       "Display a reminder about missing components");

    return 1;
}

sub _check_component {
    my ($product, $component) = @_;

    go_to_admin($sel);
    $sel->click_ok("link=components");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Edit components for which product?");

    $sel->click_ok("link=$product");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Select component of product '$product'");

    my $component_description = "$component Description";

    my $text = trim($sel->get_text("bugzilla-body"));
    if ($text =~ /$component_description/) {
        # Component exists already
        return 1;
    }

    # Add the watch user for component watching
    my $watch_user = lc $component . "@" . lc $product . ".bugs";
    $watch_user =~ s/ & /-/;
    $watch_user =~ s/\s+/\-/g;
    $watch_user =~ s/://g;

    go_to_admin($sel);
    $sel->click_ok("link=components");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Edit components for which product?");
    $sel->click_ok("link=$product");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Select component of product '$product'");
    $sel->click_ok("link=Add");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Add component to the $product product");
    $sel->type_ok("component", $component);
    $sel->type_ok("description", $component_description);
    $sel->type_ok("initialowner", $config->{'admin_user_login'});
    $sel->uncheck_ok("watch_user_auto");
    $sel->type_ok("watch_user", $watch_user);
    $sel->check_ok("watch_user_auto");
    $sel->click_ok('//input[@type="submit" and @value="Add"]');
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Component Created");
    $text = trim($sel->get_text("message"));
    ok($text eq "The component $component has been created.", "Component successfully created");

    return 1;
}

sub _check_group {
    my ($group) = @_;

    go_to_admin($sel);
    $sel->click_ok("link=Groups");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Edit Groups");

    my $group_description = "$group Description";

    my $text = trim($sel->get_text("bugzilla-body"));
    if ($text =~ /$group_description/) {
        # Group exists already
        return 1;
    }

    $sel->title_is("Edit Groups");
    $sel->click_ok("link=Add Group");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Add group");
    $sel->type_ok("name", $group);
    $sel->type_ok("desc", $group_description);
    $sel->type_ok("owner", $config->{'admin_user_login'});
    $sel->check_ok("isactive");
    $sel->check_ok("insertnew");
    $sel->click_ok("create");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("New Group Created");
    my $group_id = $sel->get_value("group_id");

    return 1;
}

sub _check_version {
    my ($product, $version) = @_;

    go_to_admin($sel);
    $sel->click_ok("link=versions");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Edit versions for which product?");
    $sel->click_ok("link=$product");
    $sel->wait_for_page_to_load(WAIT_TIME);

    my $text = trim($sel->get_text("bugzilla-body"));
    if ($text =~ /$version/) {
        # Version exists already
        return 1;
    }

    $sel->click_ok("link=Add");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_like(qr/^Add Version to Product/);
    $sel->type_ok("version", $version);
    $sel->click_ok("create");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Version Created");

    return 1;
}

sub _check_user {
    my ($user) = @_;

    go_to_admin($sel);
    $sel->click_ok("link=Users");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is("Search users");
    $sel->type_ok("matchstr", $user);
    $sel->click_ok("search");
    $sel->wait_for_page_to_load(WAIT_TIME);

    my $text = trim($sel->get_text("bugzilla-body"));
    if ($text =~ /$user/) {
        # User exists already
        return 1;
    }

    $sel->click_ok("link=add a new user");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->title_is('Add user');
    $sel->type_ok('login', $user);
    $sel->type_ok('password', 'password');
    $sel->click_ok("add");
    $sel->wait_for_page_to_load(WAIT_TIME);
    $sel->is_text_present('regexp:The user account .* has been created successfully');

    return 1;
}
