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
use Bugzilla;
use Test::More;

my $parser = Bugzilla->markdown_parser;

is(
    $parser->render_html('# header'),
    "<h1>header</h1>\n",
    'Simple header'
);

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

is(
    $parser->render_html('<script>hijack()</script>'),
    "&lt;script>hijack()&lt;/script>\n",
    'Tagfilter extension'
);

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
</tr></tbody></table>
HTML

is(
    $parser->render_html($table_markdown),
    $table_html,
    'Table extension'
);

done_testing;
