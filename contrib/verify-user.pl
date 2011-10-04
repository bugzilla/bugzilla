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
# Contributor(s): Myk Melez <myk@mozilla.org>
#                 Dave Miller <justdave@bugzilla.org>

# See if a user account has ever done anything

# ./verify-user.pl foo@baz.com

use strict;

use lib qw(.);

use Bugzilla;
use Bugzilla::Util;
use Bugzilla::DB;
use Bugzilla::Constants;

# Make sure accounts were specified on the command line and exist.
my $user = $ARGV[0] || die "You must specify an user.\n";
my $dbh = Bugzilla->dbh;
my $sth;

#$sth = $dbh->prepare("SELECT name, count(*) as qty from bugs, products where reporter=198524 and product_id=products.id group by name order by qty desc");
#$sth->execute();
#my $results = $sth->fetchall_arrayref();
#use Data::Dumper;
#print Data::Dumper::Dumper($results);
#exit;

trick_taint($user);
if ($user =~ /^\d+$/) { # user ID passed instead of email
  $sth = $dbh->prepare('SELECT login_name FROM profiles WHERE userid = ?');
  $sth->execute($user);
  ($user) = $sth->fetchrow_array || die "The user with ID $ARGV[0] does not exist.\n";
  print "User $ARGV[0]'s login name is $user.\n";
}
$sth = $dbh->prepare("SELECT userid FROM profiles WHERE login_name = ?");
$sth->execute($user);
my ($user_id) = $sth->fetchrow_array || die "The user $user does not exist.\n";

print "${user}'s ID is $user_id.\n";

$sth = $dbh->prepare("SELECT DISTINCT ipaddr FROM logincookies WHERE userid = ?");
$sth->execute($user_id);
my $iplist = $sth->fetchall_arrayref;
if (@$iplist > 0) {
    print "This user has recently connected from the following IP addresses:\n";
    foreach my $ip (@$iplist) {
        print $$ip[0] . "\n";
    }
}


# A list of tables and columns to be checked.
my $columns = {
  attachments       => ['submitter_id'] , 
  bugs              => ['assigned_to', 'reporter', 'qa_contact'] , 
  bugs_activity     => ['who'] , 
  cc                => ['who'] , 
  components        => ['initialowner', 'initialqacontact'] , 
  flags             => ['setter_id', 'requestee_id'] , 
  logincookies      => ['userid'] , 
  longdescs         => ['who'] , 
  namedqueries      => ['userid'] , 
  profiles_activity => ['userid', 'who'] , 
  quips             => ['userid'] , 
  series            => ['creator'] ,
  tokens            => ['userid'] , 
  user_group_map    => ['user_id'] , 
  votes             => ['who'] , 
  watch             => ['watcher', 'watched'] , 
  
};

my $fields = 0;
# Check records for user.
foreach my $table (keys(%$columns)) {
  foreach my $column (@{$columns->{$table}}) {
    $sth = $dbh->prepare("SELECT COUNT(*) FROM $table WHERE $column = ?");
    if ($table eq 'user_group_map') {
      $sth = $dbh->prepare("SELECT COUNT(*) FROM $table WHERE $column = ? AND grant_type = " . GRANT_DIRECT);
    }
    $sth->execute($user_id);
    my ($val) = $sth->fetchrow_array;
    $fields++ if $val;
    print "$table.$column: $val\n" if $val;
  }
}

print "The user is mentioned in $fields fields.\n";

if ($::ARGV[1] && $::ARGV[1] eq '-r') {
    if ($fields == 0) {
        $sth = $dbh->prepare("SELECT login_name FROM profiles WHERE login_name = ?");
        my $count = 0;
        print "Finding an unused recycle ID";
        do {
          $count++;
          $sth->execute(sprintf("reuseme%03d\@bugzilla.org", $count));
          print ".";
        } while (my ($match) = $sth->fetchrow_array());
        printf "\nUsing reuseme%03d\@bugzilla.org.\n", $count;
        $dbh->do("DELETE FROM user_group_map WHERE user_id=?",undef,$user_id);
        $dbh->do("UPDATE profiles SET realname='', cryptpassword='randomgarbage' WHERE userid=?",undef,$user_id);
        $dbh->do("UPDATE profiles SET login_name=? WHERE userid=?",undef,sprintf("reuseme%03d\@bugzilla.org",$count),$user_id);
    }
    else {
        print "Account has been used, so not recycling.\n";
    }
}
