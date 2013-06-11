#!/usr/bin/perl -wT
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Dave Miller <justdave@bugzilla.org>
#                 Myk Melez <myk@mozilla.org>

use 5.10.1;
use strict;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::BugMail;

my $dbh = Bugzilla->dbh;

my $list = $dbh->selectcol_arrayref(
        'SELECT bug_id FROM bugs 
          WHERE lastdiffed IS NULL
             OR lastdiffed < delta_ts 
            AND delta_ts < ' 
                . $dbh->sql_date_math('NOW()', '-', 30, 'MINUTE') .
     ' ORDER BY bug_id');

if (scalar(@$list) > 0) {
    say "OK, now attempting to send unsent mail";
    say scalar(@$list) . " bugs found with possibly unsent mail.\n";
    foreach my $bugid (@$list) {
        my $start_time = time;
        say "Sending mail for bug $bugid...";
        my $outputref = Bugzilla::BugMail::Send($bugid);
        if ($ARGV[0] && $ARGV[0] eq "--report") {
          say "Mail sent to:";
          say $_ foreach (sort @{$outputref->{sent}});
        }
        else {
            my $sent = scalar @{$outputref->{sent}};
            say "$sent mails sent.";
            say "Took " . (time - $start_time) . " seconds.\n";
        }
    }
    say "Unsent mail has been sent.";
}
