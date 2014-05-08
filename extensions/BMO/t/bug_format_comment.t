#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use lib qw( . lib );

use Test::More;
use Bugzilla;
use Bugzilla::Extension;

my $class = Bugzilla::Extension->load('extensions/BMO/Extension.pm',
                                      'extensions/BMO/Config.pm');
ok( $class->can('bug_format_comment'), 'the function exists');

my $bmo = $class->new;
ok($bmo, "got a new bmo extension");

my $text = <<'END_OF_LINKS';
# crash stats, a fake one
bp-deadbeef-deaf-beef-beed-cafefeed1337

# CVE/CAN security things
CVE-2014-0160

# svn
r2424

# bzr commit
Committing to: bzr+ssh://dlawrence%40mozilla.com@bzr.mozilla.org/bmo/4.2
modified extensions/Review/Extension.pm
Committed revision 9257.

# git with scp-style address
To gitolite3@git.mozilla.org:bugzilla/bugzilla.git
   36f56bd..eab44b1  nouri -> nouri

# git with uri (with login)
To ssh://gitolite3@git.mozilla.org/bugzilla/bugzilla.git
   36f56bd..eab44b1  withuri -> withuri

# git with uri (without login)
To ssh://git.mozilla.org/bugzilla/bugzilla.git
   36f56bd..eab44b1  nologin -> nologin
END_OF_LINKS

my @regexes;

$bmo->bug_format_comment({ regexes => \@regexes });

ok(@regexes > 0, "got some regexes to play with");

foreach my $re (@regexes) {
    my ($match, $replace) = @$re{qw(match replace)};
    if (ref($replace) eq 'CODE') {
        $text =~ s/$match/$replace->({matches => [ $1, $2, $3, $4,
                                                   $5, $6, $7, $8,
                                                   $9, $10]})/egx;
    }
    else {
        $text =~ s/$match/$replace/egx;
    }
}

my @links = (
    '<a href="https://crash-stats.mozilla.com/report/index/deadbeef-deaf-beef-beed-cafefeed1337">bp-deadbeef-deaf-beef-beed-cafefeed1337</a>',
    '<a href="http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2014-0160">CVE-2014-0160</a>',
    '<a href="http://viewvc.svn.mozilla.org/vc?view=rev&amp;revision=2424">r2424</a>',
    '<a href="http://git.mozilla.org/?p=bugzilla/bugzilla.git;a=commit;h=eab44b1">36f56bd..eab44b1  withuri -> withuri</a>',
    '<a href="http://git.mozilla.org/?p=bugzilla/bugzilla.git;a=commit;h=eab44b1">36f56bd..eab44b1  nouri -> nouri</a>',
    '<a href="http://git.mozilla.org/?p=bugzilla/bugzilla.git;a=commit;h=eab44b1">36f56bd..eab44b1  nologin -> nologin</a>',
    'http://bzr.mozilla.org/bmo/4.2/revision/9257',
);

foreach my $link (@links) {
    ok(index($text, $link) > -1, "check for $link");
}


done_testing;
