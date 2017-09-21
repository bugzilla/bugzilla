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

my ($sel, $config) = get_selenium(CHROME_MODE);
my $urlbase = $config->{bugzilla_installation};
my $admin_user = $config->{admin_user_login};

# Let's create a bug and attachment to play with.

log_in($sel, $config, 'admin');
file_bug_in_product($sel, "TestProduct");
my $bug_summary = "Security checks";
$sel->type_ok("short_desc", $bug_summary);
$sel->type_ok("comment", "This bug will be used to test security fixes.");
$sel->type_ok("data", $config->{attachment_file});
$sel->type_ok("description", "simple patch, v1");
$sel->click_ok("ispatch");
my $bug1_id = create_bug($sel, $bug_summary);


#######################################################################
# Security bug 38862.
#######################################################################

# No alternate host for attachments; cookies will be accessible.

set_parameters($sel, { "Attachments" => {"allow_attachment_display-on" => undef,
                                         "reset-attachment_base" => undef} });

go_to_bug($sel, $bug1_id);
$sel->click_ok("link=Add an attachment");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Create New Attachment for Bug #$bug1_id");
$sel->type_ok("attach_text", "<html>\n<head>\n<title>I want your cookies</title>\n<head>\n" .
                             "<body>\n<script type='text/javascript'>document.write(document.cookie);</script>\n" .
                             "</body>\n</html>", "Writing text into the attachment textarea");
$sel->type_ok("description", "show my cookies");
edit_bug($sel, $bug1_id, $bug_summary, {id => "create"});
my $alink = $sel->get_attribute('//a[@title="show my cookies"]@href');
$alink =~ /id=(\d+)/;
my $attach1_id = $1;
$sel->click_ok("link=Attachment #$attach1_id");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/Attachment $attach1_id Details for Bug $bug1_id/);
$sel->click_ok("link=edit details");
$sel->type_ok("contenttypeentry", "text/html");
edit_bug($sel, $bug1_id, $bug_summary, {id => "update"});

$sel->click_ok("link=show my cookies");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("I want your cookies");
my @cookies = split(/[\s;]+/, $sel->get_body_text());
my $nb_cookies = scalar @cookies;
ok($nb_cookies, "Found $nb_cookies cookies:\n" . join("\n", @cookies));
ok(!$sel->is_cookie_present("Bugzilla_login"), "Bugzilla_login not accessible");
ok(!$sel->is_cookie_present("Bugzilla_logincookie"), "Bugzilla_logincookie not accessible");
$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);

# Alternate host for attachments; no cookie should be accessible.

set_parameters($sel, { "Attachments" => {"attachment_base" => {type  => "text",
                                                               value => "http://127.0.0.1/$urlbase"}} });
go_to_bug($sel, $bug1_id);
$sel->click_ok("link=show my cookies");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("I want your cookies");
@cookies = split(/[\s;]+/, $sel->get_body_text());
$nb_cookies = scalar @cookies;
ok(!$nb_cookies, "No cookies found");
ok(!$sel->is_cookie_present("Bugzilla_login"), "Bugzilla_login not accessible");
ok(!$sel->is_cookie_present("Bugzilla_logincookie"), "Bugzilla_logincookie not accessible");
$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/^$bug1_id /);

set_parameters($sel, { "Attachments" => {"reset-attachment_base" => undef} });

#######################################################################
# Security bug 472362.
#######################################################################

$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("General Preferences");
my $admin_cookie = $sel->get_value("token");
logout($sel);

log_in($sel, $config, 'editbugs');
$sel->click_ok("link=Preferences");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("General Preferences");
my $editbugs_cookie = $sel->get_value("token");

# Using our own unused token is fine.

$sel->open_ok("/$urlbase/userprefs.cgi?dosave=1&display_quips=off&token=$editbugs_cookie");
$sel->title_is("General Preferences");
$sel->is_text_present_ok("The changes to your general preferences have been saved");

# Reusing a token must fail. They must all trigger the Suspicious Action warning.

my @args = ("", "token=", "token=i123x", "token=$admin_cookie", "token=$editbugs_cookie");

foreach my $arg (@args) {
    $sel->open_ok("/$urlbase/userprefs.cgi?dosave=1&display_quips=off&$arg");
    $sel->title_is("Suspicious Action");

    if ($arg eq "token=$admin_cookie") {
        $sel->is_text_present_ok("Generated by: admin <$admin_user>");
        $sel->is_text_present_ok("This token has not been generated by you");
    }
    else {
        $sel->is_text_present_ok("It looks like you didn't come from the right page");
    }
}
logout($sel);

#######################################################################
# Security bug 529416.
#######################################################################

log_in($sel, $config, 'admin');
file_bug_in_product($sel, "TestProduct");
$sel->type_ok("alias", "secret_qa_bug_" . ($bug1_id + 1));
my $bug_summary2 = "Private QA Bug";
$sel->type_ok("short_desc", $bug_summary2);
$sel->type_ok("comment", "This private bug is used to test security fixes.");
$sel->type_ok("dependson", $bug1_id);
$sel->check_ok('//input[@name="groups" and @value="Master"]');
my $bug2_id = create_bug($sel, $bug_summary2);

go_to_bug($sel, $bug1_id);
$sel->is_text_present_ok("secret_qa_bug_$bug2_id");
logout($sel);

log_in($sel, $config, 'editbugs');
go_to_bug($sel, $bug1_id);
ok(!$sel->is_text_present("secret_qa_bug_$bug2_id"), "The alias 'secret_qa_bug_$bug2_id' is not visible for unauthorized users");
$sel->is_text_present_ok($bug2_id);
logout($sel);

go_to_bug($sel, $bug1_id);
ok(!$sel->is_text_present("secret_qa_bug_$bug2_id"), "The alias 'secret_qa_bug_$bug2_id' is not visible for logged out users");
$sel->is_text_present_ok($bug2_id);

#######################################################################
# Security bug 472206.
# Keep this test as the very last one as the File Saver will remain
# open till the end of the script. Selenium is currently* unable
# to interact with it and close it (* = 2.6.0).
#######################################################################

log_in($sel, $config, 'admin');
set_parameters($sel, { "Attachments" => {"allow_attachment_display-off" => undef} });

# Attachments are not viewable.

go_to_bug($sel, $bug1_id);
$sel->click_ok("link=Details");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/Attachment \d+ Details for Bug $bug1_id/);
$sel->is_text_present_ok("The attachment is not viewable in your browser due to security restrictions");
$sel->click_ok("link=View");
# Wait 1 second to give the browser a chance to display the attachment.
# Do not use wait_for_page_to_load_ok() as the File Saver will never go away.
sleep(1);
ok(!$sel->is_text_present('@@'), "Patch not displayed");

# Enable viewing attachments.

set_parameters($sel, { "Attachments" => {"allow_attachment_display-on" => undef} });

go_to_bug($sel, $bug1_id);
$sel->click_ok('link=simple patch, v1');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("");
$sel->is_text_present_ok('@@');
$sel->go_back_ok();
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/$bug1_id /);
logout($sel);
