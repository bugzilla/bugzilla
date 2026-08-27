# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.


##################
#Bugzilla Test 15#
####Productform###

use 5.14.0;
use strict;
use warnings;

use File::Spec;
use Test::More;

my $node;
foreach my $dir (File::Spec->path()) {
  foreach my $name (qw(node node.exe)) {
    my $path = File::Spec->catfile($dir, $name);
    if (-x $path && !-d $path) {
      $node = $path;
      last;
    }
  }
  last if $node;
}

plan skip_all => 'Node.js is required to test js/productform.js' if !$node;

my $script = <<'JS';
var fs = require('fs');
var vm = require('vm');

vm.runInThisContext(
  fs.readFileSync('js/productform.js', 'utf8'),
  { filename: 'js/productform.js' }
);

console.log(
  merge_arrays(
    ['Trunk', '2.0'],
    ['unspecified', 'Trunk'],
    false
  ).join('\t')
);
console.log(
  merge_arrays(
    ['Beta', 'alpha'],
    [{ value: 'ALPHA' }, { value: 'Release' }],
    true
  ).join('\t')
);
JS

my $pid = open(my $fh, '-|', $node, '-e', $script);
if (!defined $pid) {
  plan tests => 1;
  fail("could not run $node: $!");
  exit;
}

my @results = <$fh>;
close($fh);
my $status = $?;

if ($status || @results != 2) {
  plan tests => 1;
  fail('js/productform.js did not produce the expected test output');
  diag("Node.js exit status: $status");
  diag("Node.js output:\n" . join('', @results));
  exit;
}

chomp(@results);
plan tests => 2;

is_deeply(
  [split(/\t/, $results[0])],
  ['2.0', 'Trunk', 'unspecified'],
  'unsorted product values are sorted and de-duplicated'
);
is_deeply(
  [split(/\t/, $results[1])],
  ['alpha', 'Beta', 'Release'],
  'select options are merged, sorted, and de-duplicated'
);
