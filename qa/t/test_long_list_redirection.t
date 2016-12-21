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

$sel->open_ok("/$config->{bugzilla_installation}/long_list.cgi?id=1");
$sel->title_is("Full Text Bug Listing", "Display bug as format for printing");
my $text = $sel->get_text("//h1");
$text =~ s/[\r\n\t\s]+/ /g;
is($text, 'Bug 1', 'Display bug 1 specifically');
