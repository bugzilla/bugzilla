#!/usr/bin/perl -w
use strict;
use feature 'say';

use FindBin qw( $RealBin );
use lib "$RealBin/..";
use lib "$RealBin/../lib";

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::User;
use Bugzilla::User::APIKey;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $login = shift
    or die "syntax: $0 bugzilla-login [description]\n";
my $description = shift;

my $user = Bugzilla::User->check({ name => $login });
my $api_key = Bugzilla::User::APIKey->create({
    user_id     => $user->id,
    description => $description,
});
say $api_key->api_key;
