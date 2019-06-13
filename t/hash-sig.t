# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );
use Bugzilla::Util qw(generate_random_password);
use Bugzilla::Token qw(issue_hash_sig check_hash_sig);
use Bugzilla::Localconfig;
use Test2::V0;
use Test2::Mock qw(mock);

my $site_wide_secret = generate_random_password(256);
my $Localconfig = mock 'Bugzilla::Localconfig' => (
  add_constructor => [fake_new => 'ref_copy'],
  override => [
    site_wide_secret => sub { $site_wide_secret },
  ]
);

{
  package Bugzilla;
  sub localconfig { Bugzilla::Localconfig->fake_new({}) }
}

my $sig = issue_hash_sig("hero", "batman");
ok(check_hash_sig("hero", $sig, "batman"), "sig for batman checks out");

done_testing();
