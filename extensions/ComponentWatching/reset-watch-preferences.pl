#!/usr/bin/perl

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
# The Original Code is the Component Watching Extension
#
# The Initial Developer of the Original Code is the Mozilla Foundation
# Portions created by the Initial Developers are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Byron Jones <bjones@mozilla.com>

use strict;
use warnings;

use lib '.';
$| = 1;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Install::Util qw(indicate_progress);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my @DEFAULT_EVENTS = qw(0 2 3 4 5 6 7 9 10 50);
my $REL_COMP_WATCH = 15;

print "This script resets the component watching preferences back to\n";
print "default values.  It is required to be run when upgrading from\n";
print "version 1.0 to 1.1\n";
print "Press <ENTER> to start, or CTRL+C to cancel... ";
getc();
print "\n";

my $dbh = Bugzilla->dbh;

$dbh->bz_start_transaction();

my @users;
my $ra_user_ids = $dbh->selectcol_arrayref(
    "SELECT DISTINCT user_id FROM component_watch"
);

my $total = scalar @$ra_user_ids;
my $count = 0;
foreach my $user_id (@$ra_user_ids) {
    indicate_progress({ current => $count++, total => $total }) if $total > 10;
    $dbh->do(
        "DELETE FROM email_setting WHERE user_id=? AND relationship=?",
        undef,
        $user_id, $REL_COMP_WATCH
    );
    foreach my $event (@DEFAULT_EVENTS) {
        $dbh->do(
            "INSERT INTO email_setting(user_id,relationship,event) VALUES (?,?,?)",
            undef,
            $user_id, $REL_COMP_WATCH, $event
        );
    }
}

$dbh->bz_commit_transaction();

print "Done.\n";
