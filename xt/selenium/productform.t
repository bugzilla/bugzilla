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

use QA::Util;
use Test::More "no_plan";

my ($sel, $config) = get_selenium();

log_in($sel, $config, 'admin');
$sel->open_ok("/$config->{bugzilla_installation}/editflagtypes.cgi");
$sel->title_is("Administer Flag Types");

my $script = <<'JS';
var arrayResult = document.createElement('div');
arrayResult.id = 'merge_arrays_result';
arrayResult.appendChild(document.createTextNode(
  merge_arrays(
    ['Trunk', '2.0'],
    ['unspecified', 'Trunk'],
    false
  ).join('|')
));
document.body.appendChild(arrayResult);

var selectResult = document.createElement('div');
selectResult.id = 'merge_select_result';
selectResult.appendChild(document.createTextNode(
  merge_arrays(
    ['Beta', 'alpha'],
    [{ value: 'ALPHA' }, { value: 'Release' }],
    true
  ).join('|')
));
document.body.appendChild(selectResult);
JS

$sel->run_script($script);
$sel->text_is(
  'merge_arrays_result',
  '2.0|Trunk|unspecified',
  'unsorted product values are sorted and de-duplicated'
);
$sel->text_is(
  'merge_select_result',
  'alpha|Beta|Release',
  'select options are merged, sorted, and de-duplicated'
);

logout($sel);
