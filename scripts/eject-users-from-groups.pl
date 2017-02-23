#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);



use Getopt::Long;

use Bugzilla;
use Bugzilla::Constants;

BEGIN { Bugzilla->extensions }

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $dbh = Bugzilla->dbh;
my @remove_group_names;
my $nobody_name = 'nobody@mozilla.org';
my $admin_name = 'automation@bmo.tld';

GetOptions(
    'nobody=s' => \$nobody_name,
    'admin=s'  => \$admin_name,
    'group|G=s@' => \@remove_group_names,
);
my @user_names = @ARGV;

unless (@remove_group_names) {
    die "usage: $0 [--admin=$admin_name] [--nobody=$nobody_name] ",
      "-G legal -G finance dylan\@mozilla.com bob\@example.net\n";
}

$dbh->bz_start_transaction();
my ($timestamp) = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
my $admin_user  = Bugzilla::User->check({ name => $admin_name });
my $nobody_user = Bugzilla::User->check({ name => $nobody_name });
Bugzilla->set_user($admin_user);

my @remove_groups = map { Bugzilla::Group->check({name => $_}) } @remove_group_names;

foreach my $user_name (@user_names) {
    my $user = Bugzilla::User->check({name => $user_name});
    say 'Working on ', $user->identity;

    $user->force_bug_dissociation($nobody_user, \@remove_groups, $timestamp);
}

$dbh->bz_commit_transaction();
