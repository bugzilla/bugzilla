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
set_parameters($sel, { "Bug Fields" => {"useclassification-on" => undef} });

# Do not use file_bug_in_product() because our goal here is not to file
# a bug but to check what is present in the UI, and also to make sure
# that we get exactly the right page with the right information.
#
# The admin is not a member of the "QA‑Selenium‑TEST" group, and so
# cannot see the "QA‑Selenium‑TEST" product.

$sel->click_ok("link=New");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Enter Bug");
$sel->click_ok("link=Other Products", undef, "Choose full product list");
$sel->wait_for_page_to_load(WAIT_TIME);
$sel->title_is("Enter Bug");
ok(!$sel->is_text_present("QA-Selenium-TEST"), "The QA-Selenium-TEST product is not displayed");
logout($sel);

# Same steps, but for a member of the "QA‑Selenium‑TEST" group.
# The "QA‑Selenium‑TEST" product must be visible to him.

log_in($sel, $config, 'QA_Selenium_TEST');
$sel->click_ok("link=New");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Enter A Bug");
if ($sel->is_text_present('None of the above; my bug is in')) {
    $sel->click_ok('advanced_link');
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Enter Bug");
}
$sel->click_ok('link=Other Products');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("QA-Selenium-TEST");
# For some unknown reason, Selenium doesn't like hyphens in links.
# $sel->click_ok("link=QA-Selenium-TEST");
$sel->click_ok('//div[@id="choose_product"]//a[contains(@href, "QA-Selenium-TEST")]');
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->is_text_present_ok("Product: QA-Selenium-TEST");
logout($sel);
