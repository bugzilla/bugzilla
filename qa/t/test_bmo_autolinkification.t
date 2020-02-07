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

log_in($sel, $config, 'unprivileged');
file_bug_in_product($sel, 'TestProduct');
my $bug_summary = "linkification test bug";
$sel->type_ok("short_desc", $bug_summary);
$sel->type_ok("comment",    "linkification test");
$sel->click_ok("commit");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/\d+ \S $bug_summary/, "Bug created");
my $bug_id = $sel->get_value("//input[\@name='id' and \@type='hidden']");

$sel->type_ok("comment", "bp-63f096f7-253b-4ee2-ae3d-8bb782090824");
$sel->click_ok("bottom-save-btn");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/\d+ \S $bug_summary/, "crash report added");
go_to_bug($sel, $bug_id);
attribute_is($sel, 'bp-63f096f7-253b-4ee2-ae3d-8bb782090824',
  'https://crash-stats.mozilla.org/report/index/63f096f7-253b-4ee2-ae3d-8bb782090824'
);

$sel->type_ok("comment", "CVE-2010-2884");
$sel->click_ok("bottom-save-btn");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/\d+ \S $bug_summary/, "cve added");
go_to_bug($sel, $bug_id);
attribute_is($sel, 'CVE-2010-2884',
  'https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2010-2884');

$sel->type_ok("comment", "r12345");
$sel->click_ok("bottom-save-btn");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_like(qr/\d+ \S $bug_summary/, "svn revision added");
go_to_bug($sel, $bug_id);
attribute_is($sel, 'r12345',
  'https://viewvc.svn.mozilla.org/vc?view=rev&revision=12345');

logout($sel);

sub attribute_is {
  my ($sel, $text, $href) = @_;
  my $element = $sel->find_element(qq{//a[contains(text(),"$text")]});
  if ($element) {
    ok($element->get_attribute('href') eq $href, "Attribute is: $href");
    return;
  }
  ok(0, "Attribute is: $href");
}

