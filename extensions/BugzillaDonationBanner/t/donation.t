#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.14.0;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Extension;
use DateTime;
use Test::More;

my $Ext = Bugzilla::Extension->load(
  'extensions/BugzillaDonationBanner/Extension.pm',
  'extensions/BugzillaDonationBanner/Config.pm',
);
my $Donation = "${Ext}::Donation";
my $get_banner = $Donation->can('get_banner');
my $save_preference = $Donation->can('save_preference');
my $dismiss = $Donation->can('dismiss');
my $current_user;
my $params = {donation_banner_visibility => 'admins_only'};

{
  no strict 'refs';
  no warnings 'redefine';
  *Bugzilla::user = sub { return $current_user };
  *Bugzilla::params = sub { return $params };
  *Bugzilla::local_timezone = sub { return 'UTC' };
  *{"${Donation}::issue_hash_token"} = sub { return 'test-token' };
  *{"${Donation}::clear_settings_cache"} = sub { return };
  *{"${Donation}::ThrowUserError"} = sub { die $_[0] };
}

{
  no warnings 'redefine';
  *DateTime::now = sub {
    return DateTime->new(
      year => 2026, month => 12, day => 28, hour => 12, time_zone => 'UTC'
    );
  };
}

sub new_user {
  my ($id, $admin) = @_;
  return bless {
    id       => $id,
    admin    => $admin,
    settings => {
      donate_banner_pref => Local::Setting->new('next_upgrade'),
      donate_banner_last_version => Local::Setting->new('0.0'),
      donate_banner_reminder_date => Local::Setting->new('1970-01-01'),
    },
  }, 'Local::User';
}

sub set_state {
  my ($user, %state) = @_;
  for my $name (keys %state) {
    $user->{settings}{"donate_banner_$name"}->set($state{$name});
  }
  $current_user = $user;
}

sub stored {
  my ($user, $name) = @_;
  return $user->{settings}{"donate_banner_$name"}->value;
}

subtest 'visibility' => sub {
  my $admin = new_user(1, 1);
  my $plain = new_user(2, 0);
  my $anon  = new_user(0, 0);

  for my $case (
    ['disabled',    0, 0],
    ['admins_only', 1, 0],
    ['end_users',   1, 1],
  ) {
    my ($mode, $admin_sees, $plain_sees) = @$case;
    $params->{donation_banner_visibility} = $mode;
    set_state($admin, pref => 'next_upgrade', last_version => '0.0');
    is(!!$get_banner->(), !!$admin_sees, "admin, $mode");
    set_state($plain, pref => 'next_upgrade', last_version => '0.0');
    is(!!$get_banner->(), !!$plain_sees, "plain user, $mode");
  }

  $params->{donation_banner_visibility} = 'end_users';
  set_state($anon);
  is($get_banner->(1), undef, 'anonymous users never see a banner');
};

subtest 'preferences and banner data' => sub {
  my $admin = new_user(1, 1);
  $params->{donation_banner_visibility} = 'admins_only';
  set_state($admin, pref => 'next_upgrade', last_version => '0.0');
  my $banner = $get_banner->();

  ok($banner, 'banner is due after installation');
  is($banner->{url}, 'https://bugzilla.org/donate', 'donation URL');
  is($banner->{token}, 'test-token', 'hash token is included');
  is($banner->{today}, '2026-12-28', 'today is supplied');
  like($banner->{visibility_note}, qr/only shown .* admin privs/,
    'admins-only mode explains visibility');
  ok(!$banner->{show_thanks}, 'fresh installations are not thanked');

  set_state($admin, pref => 'next_upgrade', last_version => '1.0');
  ok($get_banner->()->{show_thanks}, 'admins are thanked after upgrade');

  set_state($admin, pref => 'next_upgrade', last_version => BUGZILLA_VERSION);
  is($get_banner->(), undef, 'hidden after dismissal on this version');
  ok($get_banner->(1), 'ignore_preference still builds the banner');

  set_state($admin, pref => 'specific_date', reminder_date => '2026-12-28');
  ok($get_banner->(), 'reminder due today');
  set_state($admin, pref => 'specific_date', reminder_date => '2026-12-29');
  is($get_banner->(), undef, 'future reminder is not due');
  set_state($admin, pref => 'never');
  is($get_banner->(), undef, 'never preference hides the banner');
};

subtest 'save_preference validates and stamps settings' => sub {
  my $admin = new_user(1, 1);
  set_state($admin, pref => 'never', last_version => '1.0');

  $save_preference->('specific_date', '2030-05-17');
  is(stored($admin, 'pref'), 'specific_date', 'specific_date is saved');
  is(stored($admin, 'reminder_date'), '2030-05-17', 'date is saved');
  is(stored($admin, 'last_version'), BUGZILLA_VERSION, 'version is stamped');

  for my $date ('', 'not-a-date', '2030-02-30') {
    eval { $save_preference->('specific_date', $date) };
    like($@, qr/illegal_date/, "rejects invalid date '$date'");
  }
  eval { $save_preference->('bogus', '') };
  like($@, qr/invalid_parameter/, 'rejects an unknown preference');
};

subtest 'dismissal choices' => sub {
  my $admin = new_user(1, 1);

  set_state($admin);
  $dismiss->('week');
  is(stored($admin, 'reminder_date'), '2027-01-04', 'week is seven days');

  set_state($admin);
  $dismiss->('month');
  is(stored($admin, 'reminder_date'), '2027-01-27', 'month is thirty days');

  set_state($admin);
  $dismiss->('date', '2031-02-03');
  is(stored($admin, 'reminder_date'), '2031-02-03', 'chosen date is saved');

  set_state($admin);
  $dismiss->('never');
  is(stored($admin, 'pref'), 'never', 'never is saved');

  set_state($admin, pref => 'specific_date');
  $dismiss->('next_upgrade');
  is(stored($admin, 'pref'), 'next_upgrade', 'next upgrade is saved');
};

done_testing;

package Local::Setting;

sub new { return bless {value => $_[1]}, $_[0] }
sub value { return $_[0]->{value} }
sub set { $_[0]->{value} = $_[1]; return }

package Local::User;

sub id { return $_[0]->{id} }
sub in_group { return $_[1] eq 'admin' && $_[0]->{admin} }
sub settings { return $_[0]->{settings} }
