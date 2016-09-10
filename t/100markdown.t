# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Enforce high standards against code that will be installed

use 5.14.0;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5 t);
use Test2::Bundle::Extended;
use Bugzilla::Util;
BEGIN {
    my $terms = {
        "bug"               => "bug",
        "Bug"               => "Bug",
        "abug"              => "a bug",
        "Abug"              => "A bug",
        "aBug"              => "a Bug",
        "ABug"              => "A Bug",
        "bugs"              => "bugs",
        "Bugs"              => "Bugs",
        "comment"           => "comment",
        "comments"          => "comments",
        "zeroSearchResults" => "Zarro Boogs found",
        "Bugzilla"          => "Bugzilla"
    };
    no warnings 'redefine', 'once';
    *Bugzilla::Util::template_var = sub {
        my $name = shift;
        if ($name eq 'terms') {
            return $terms;
        } else {
            die "sorry!";
        }
    };
}
use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Bug;
use Bugzilla::Comment;
use Bugzilla::User;
use Bugzilla::Markdown;

Bugzilla->usage_mode(USAGE_MODE_TEST);
Bugzilla->error_mode(ERROR_MODE_DIE);

my $user_mock = mock 'Bugzilla::User' => (
    override_constructor => ['new', 'hash'],
);

my $comment_mock = mock 'Bugzilla::Comment' => (
    add_constructor => ['new', 'hash'],
);

my $bug_mock = mock 'Bugzilla::Bug' => (
    override_constructor => ['new', 'hash'],
);

# mocked objects just take all constructor args and put them into the hash.
my $user = Bugzilla::User->new(
    userid => 33,
    settings => { use_markdown => { is_enabled => 1, value => 'on' } },
);
my $bug = Bugzilla::Bug->new(bug_id => 666);
my $comment = Bugzilla::Comment->new(already_wrapped => 0);

Bugzilla->set_user($user);

my $markdown_text = <<MARKDOWN;
```
this is a block
> with an embedded blockquote
```
MARKDOWN

my $markdown = Bugzilla::Markdown->new();

ok($markdown, "got a new markdown object");
my $markdown_html = $markdown->markdown($markdown_text, $bug, $comment);
is("<pre><code>this is a block\n"
    . "&gt; with an embedded blockquote</code></pre>\n",
    $markdown_html, "code block with embedded block quote");

done_testing;
