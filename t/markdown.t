# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.10.1;
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );

use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams (password_complexity => 'no_constraints');
use Bugzilla;
use Test2::V0;

my $have_cmark_gfm = eval {
    require Alien::libcmark_gfm;
    require Bugzilla::Markdown::GFM;
};

plan skip_all => "these tests require Alien::libcmark_gfm" unless $have_cmark_gfm;

my $parser = Bugzilla->markdown;

is($parser->render_html('# header'), "<h1>header</h1>\n", 'Simple header');

is(
  $parser->render_html('`code snippet`'),
  "<p><code>code snippet</code></p>\n",
  'Simple code snippet'
);

is(
  $parser->render_html('http://bmo-web.vm'),
  "<p><a href=\"http://bmo-web.vm\">http://bmo-web.vm</a></p>\n",
  'Autolink extension'
);

SKIP: {
  skip("currently no raw html is allowed via the safe option", 1);
  is(
    $parser->render_html('<script>hijack()</script>'),
    "&lt;script&gt;hijack()&lt;/script&gt;\n",
    'Tagfilter extension'
  );
}

is(
  $parser->render_html('~~strikethrough~~'),
  "<p><del>strikethrough</del></p>\n",
  'Strikethrough extension'
);

my $table_markdown = <<'MARKDOWN';
| Col1 | Col2 |
| ---- |:----:|
| val1 | val2 |
MARKDOWN

my $table_html = <<'HTML';
<table>
<thead>
<tr>
<th>Col1</th>
<th align="center">Col2</th>
</tr>
</thead>
<tbody>
<tr>
<td>val1</td>
<td align="center">val2</td>
</tr>
</tbody>
</table>
HTML

is($parser->render_html($table_markdown), $table_html, 'Table extension');

done_testing;
