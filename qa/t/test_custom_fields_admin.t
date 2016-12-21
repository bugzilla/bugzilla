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

# Create a custom field, going through each type available,
# mark it as obsolete and delete it immediately.

go_to_admin($sel);
$sel->click_ok("link=Custom Fields");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_is("Custom Fields");

my @types = ("Bug ID", "Large Text Box", "Free Text", "Multiple-Selection Box",
             "Drop Down", "Date/Time");
my $counter = int(rand(10000));

foreach my $type (@types) {
    my $fname = "cf_field" . ++$counter;
    my $fdesc = "Field" . $counter;

    $sel->click_ok("link=Add a new custom field");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Add a new Custom Field");
    $sel->type_ok("name", $fname);
    $sel->type_ok("desc", $fdesc);
    $sel->select_ok("type", "label=$type");
    $sel->click_ok("obsolete");
    $sel->click_ok("create");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Custom Field Created");
    $sel->click_ok("//a[\@href='editfields.cgi?action=del&name=$fname']");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Delete the Custom Field '$fname' ($fdesc)");
    $sel->click_ok("link=Delete field '$fdesc'");
    $sel->wait_for_page_to_load_ok(WAIT_TIME);
    $sel->title_is("Custom Field Deleted");
}

logout($sel);
