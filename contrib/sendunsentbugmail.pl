#!/usr/bin/perl -wT
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::BugMail;

my $dbh = Bugzilla->dbh;

my $list = $dbh->selectcol_arrayref(
        'SELECT bug_id FROM bugs
          WHERE (lastdiffed IS NULL OR lastdiffed < delta_ts)
            AND delta_ts < '
                . $dbh->sql_date_math('NOW()', '-', 30, 'MINUTE') .
     ' ORDER BY bug_id');

if (scalar(@$list) > 0) {
    print "OK, now attempting to send unsent mail\n";
    print scalar(@$list) . " bugs found with possibly unsent mail.\n\n";
    foreach my $bugid (@$list) {
        my $start_time = time;
        print "Sending mail for bug $bugid...\n";
        my $outputref = Bugzilla::BugMail::Send($bugid);
        if ($ARGV[0] && $ARGV[0] eq "--report") {
          print "Mail sent to:\n";
          foreach (sort @{$outputref->{sent}}) {
              print $_ . "\n";
          }
          
          print "Excluded:\n";
          foreach (sort @{$outputref->{excluded}}) {
              print $_ . "\n";
          }
        }
        else {
            my ($sent, $excluded) = (scalar(@{$outputref->{sent}}),scalar(@{$outputref->{excluded}}));
            print "$sent mails sent, $excluded people excluded.\n";
            print "Took " . (time - $start_time) . " seconds.\n\n";
        }    
    }
    print "Unsent mail has been sent.\n";
}
