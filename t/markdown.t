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
use Bugzilla::Test::MockLocalconfig urlbase => 'http://bmo-web.vm/';
use Bugzilla::Test::MockParams (password_complexity => 'no_constraints');
use Mojo::DOM;
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
  $parser->render_html('https://www.mozilla.org'),
  "<p><a href=\"https://www.mozilla.org\" rel=\"nofollow\">https://www.mozilla.org</a></p>\n",
  'Autolink extension'
);

SKIP: {
  skip("currently no raw HTML is allowed via the safe option", 1);
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

my $angle_link =  $parser->render_html("<https://searchfox.org/mozilla-central/rev/76fe4bb385348d3f45bbebcf69ba8c7283dfcec7/mobile/android/base/java/org/mozilla/gecko/toolbar/SecurityModeUtil.java#101>");
my $angle_link_dom = Mojo::DOM->new($angle_link);
my $ahref = $angle_link_dom->at('a[href]');
is($ahref->attr('href'), 'https://searchfox.org/mozilla-central/rev/76fe4bb385348d3f45bbebcf69ba8c7283dfcec7/mobile/android/base/java/org/mozilla/gecko/toolbar/SecurityModeUtil.java#101', 'angle links are parsed properly');

is($parser->render_html('<foo>'), "<p>&lt;foo&gt;</p>\n", "literal tags work");

done_testing;
