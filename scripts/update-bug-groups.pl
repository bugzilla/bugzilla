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


$| = 1;

use Bugzilla;
use Bugzilla::CGI;
use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::Search;
use Bugzilla::User;
use Getopt::Long qw(GetOptions);
use URI;
use URI::QueryParam;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $options = {};
GetOptions($options, 'add=s', 'remove=s') or exit(1);
my $url = URI->new(shift);
unless ($url && ($options->{add} || $options->{remove})) {
    die <<EOF;
Syntax:
    update-bug-groups.pl [--add group-name] [--remove group-name] buglist-url

Synopsis:
    This script finds bugs matching the search URL and:

    --add : adds the provided group to bugs
    --remove : removes the provided group from bugs

    At least --add or --remove must be specified; both options can be provided
    at the same time.

EOF
}
die "Invalid buglist.cgi query\n" unless $url->path =~ m#/buglist\.cgi$#;
$url->query_param( limit => 0 );

my ($add_group, $remove_group);
$add_group = Bugzilla::Group->check({ name => $options->{add} }) if $options->{add};
$remove_group = Bugzilla::Group->check({ name => $options->{remove} }) if $options->{remove};

my $user = Bugzilla::User->check({ name => 'automation@bmo.tld' });
$user->{groups} = [ Bugzilla::Group->get_all ];
$user->{bless_groups} = [ Bugzilla::Group->get_all ];
Bugzilla->set_user($user);

# find the bugs

my $params = Bugzilla::CGI->new($url->query);
my $search = Bugzilla::Search->new(
    fields => [ 'bug_id', 'short_desc' ],
    params => scalar $params->Vars,
    user   => $user,
);
my $bugs = $search->data;
my $count = scalar @$bugs;

# update

die "No bugs found\n" unless $count;
print "Query matched $count bug(s)\nPress <Ctrl-C> to stop or <Enter> to continue..\n";
getc();

my $dbh = Bugzilla->dbh;
my $updated = 0;
foreach my $ra (@$bugs) {
    $dbh->bz_start_transaction;
    my ($bug_id, $summary) = @$ra;
    print "$bug_id - $summary\n";
    my $bug = Bugzilla::Bug->check($bug_id);
    $bug->add_group($add_group) if $add_group;
    $bug->remove_group($remove_group) if $remove_group;
    my $changes = $bug->update();
    if (scalar keys %$changes) {
        $dbh->do("UPDATE bugs SET lastdiffed = delta_ts WHERE bug_id = ?", undef, $bug->id);
        $updated++;
    }
    $dbh->bz_commit_transaction;

    # drop cached user objects to avoid excessive memory usage
    Bugzilla::User->object_cache_clearall();
}

print "\nUpdated $updated bugs(s)\n";
