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
set_parameters($sel, { "Bug Change Policies" => {"letsubmitterchoosepriority-off" => undef} });
file_bug_in_product($sel, "TestProduct");
ok(!$sel->is_text_present("Priority"), "The Priority label is not present");
ok(!$sel->is_element_present("//select[\@name='priority']"), "The Priority drop-down menu is not present");
set_parameters($sel, { "Bug Change Policies" => {"letsubmitterchoosepriority-on" => undef} });
file_bug_in_product($sel, "TestProduct");
$sel->is_text_present_ok("Priority");
$sel->is_element_present_ok("//select[\@name='priority']");
logout($sel);
