#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(. lib local/lib/perl5);
use feature 'say';


use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::User;
use Bugzilla::Group;
use Getopt::Long qw(:config gnu_getopt);

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($users_file, $group, $admin);
my ($do_adds, $do_removes) = (0, 0);

GetOptions('admin=s'      => \$admin,
           'users-file=s' => \$users_file,
           'do-adds'      => \$do_adds,
           'do-removes'   => \$do_removes,
           'group=s'      => \$group);

usage() unless $admin && $users_file && $group;

Bugzilla->set_user(Bugzilla::User->check({name => $admin}));

my $group_obj = Bugzilla::Group->check({name => $group});

my %old_member = map { $_->name => $_ } @{$group_obj->members_direct()};
my %new_member;
my @missing;

open my $fh, '<', $users_file or die "Unable to open $users_file: $!";
while (my $user_name = <$fh>) {
    chomp $user_name;
    eval {
        my $user = Bugzilla::User->check({name => $user_name});
        $new_member{ $user->name } = $user;
    };
    if ($@) {
        push @missing, $user_name;
    }
}

my @removes = map  { $old_member{$_} } grep { !$new_member{$_} } keys %old_member;
my @adds    = map  { $new_member{$_} } grep { !$old_member{$_} } keys %new_member;

if (@removes == 0 && @adds == 0) {
    if (@missing != 0) {
        printf STDERR "There are %d user(s) in %s that do not exist.\n",
          scalar @missing, $users_file;
    }
    say STDERR "Nothing to do\n";
    exit;
}

$| = 1;
printf STDERR "Group '%s', Admin '%s'\n", $group, $admin;
printf STDERR "Will add %d user(s)\n", scalar @adds if $do_adds;
printf STDERR "Will remove %d user(s)\n", scalar @removes if $do_removes;
printf STDERR "There are %d user(s) in %s that do not exist.\n", scalar @missing, $users_file
  if @missing;
say STDERR "Press <Ctrl-C> to stop or <Enter> to continue...";
getc();

say "missing $_\n" foreach @missing;

my $dbh = Bugzilla->dbh;
$dbh->bz_start_transaction();

if ($do_removes) {
    foreach my $remove (@removes) {
        say "remove ", $remove->login, " from ", $group;
        $remove->set_groups({ remove => [$group] });
        $remove->update;
    }
}

if ($do_adds) {
    foreach my $add (@adds) {
        say "add ", $add->login, " to ", $group;
        $add->set_groups({ add => [$group] });
        $add->update;
    }
}

$dbh->bz_commit_transaction();

say STDERR "done.\n";

Bugzilla->memcached->clear_all();

sub usage {
    die <<EOF;
usage $0 --admin bob\@mozilla.org --users-file users.txt --group pants

--users-file  File containing one bugzilla email per line.
--admin      Admin user capable of adding people to the group.
--group      Group name to add users from user.txt into.
--do-adds    Add users in users-file to the group.
--do-removes Remove users NOT in users-file from the group.

Informational messages are sent to STDERR. STDOUT should be redirected to a file
as it will contain a list of which users were added, removed, and any missing users.
EOF
}