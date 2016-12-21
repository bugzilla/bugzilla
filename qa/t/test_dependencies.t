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

# Let's create a public and a private bug.

log_in($sel, $config, 'admin');
file_bug_in_product($sel, "TestProduct");
my $bug_summary = "Dependency Checks";
$sel->type_ok("short_desc", $bug_summary);
$sel->type_ok("comment", "This bug is public");
my $bug1_id = create_bug($sel, $bug_summary);

file_bug_in_product($sel, "TestProduct");
$sel->type_ok("alias", "secret_qa_bug_$bug1_id+1");
my $bug_summary2 = "Big Ben";
$sel->type_ok("short_desc", $bug_summary2);
$sel->type_ok("comment", "This bug is private");
$sel->type_ok("dependson", $bug1_id);
$sel->check_ok('//input[@name="groups" and @value="Master"]');
my $bug2_id = create_bug($sel, $bug_summary2);

go_to_bug($sel, $bug1_id);
$sel->click_ok("link=Mark as Duplicate");
$sel->type_ok("dup_id", $bug2_id);
edit_bug_and_return($sel, $bug1_id, $bug_summary);
$sel->is_text_present_ok("secret_qa_bug_$bug1_id+1");
logout($sel);

# A user with editbugs privs who cannot see some bugs in the dependency list
# or the bug this duplicate points to should still be able to edit this bug.

log_in($sel, $config, 'editbugs');
go_to_bug($sel, $bug1_id);
ok(!$sel->is_text_present("secret_qa_bug_$bug1_id+1"), "The alias of the private bug is not visible");
$sel->select_ok("priority", "label=High");
$sel->select_ok("bug_status", "VERIFIED");
$sel->type_ok("comment", "Can I still edit this bug?");
edit_bug($sel, $bug1_id);
logout($sel);
