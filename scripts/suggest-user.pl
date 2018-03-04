#!/usr/bin/perl
use strict;
use warnings;
use FindBin qw($RealBin);
use lib ($RealBin);
use Bugzilla;
use Search::Elasticsearch;
use Bugzilla::Elastic;

my $elastic = Bugzilla::Elastic->new(
    es_client => Search::Elasticsearch->new()
);
my $user = Bugzilla::User->check({name => 'dylan@mozilla.com'});
Bugzilla->set_user($user);
my $users;

for (1..4) {
    $users = $elastic->suggest_users($ARGV[0]);
}
print "$_->{name}\n" for @$users;
