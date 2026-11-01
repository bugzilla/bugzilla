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
use Bugzilla::Extension;
use Test::More;

my $Ext = Bugzilla::Extension->load(
  'extensions/BugzillaDonationBanner/Extension.pm',
  'extensions/BugzillaDonationBanner/Config.pm',
);
require Bugzilla::Extension::BugzillaDonationBanner::Config;

my @settings;
my $donation = {banner => 1};
my $user = bless {settings => {}}, 'Local::User';
my $cgi = bless {params => {}}, 'Local::CGI';

{
  no strict 'refs';
  no warnings 'once';
  no warnings 'redefine';
  *{"${Ext}::add_setting"} = sub { push @settings, [@_] };
  *{"${Ext}::bz_locations"} = sub { return {extensionsdir => 'extensions'} };
  *Bugzilla::Install::Filesystem::_group = sub { return 0 };
  *Bugzilla::user = sub { return $user };
  *Bugzilla::cgi = sub { return $cgi };
  *Bugzilla::params = sub { return {donation_banner_visibility => 'end_users'} };
  *{"${Ext}::Donation::get_banner"} = sub { return $donation };
  *{"${Ext}::Donation::today"} = sub { return '2026-11-01' };
  *{"${Ext}::Donation::save_preference"} = sub { $main::saved = [@_] };
}

subtest 'metadata and parameter panel' => sub {
  is($Ext->NAME, 'BugzillaDonationBanner', 'extension name');

  my $Config = "${Ext}::Config";
  my ($param) = $Config->get_param_list;
  is($param->{name}, 'donation_banner_visibility', 'visibility parameter');
  is($param->{default}, 'admins_only', 'defaults to admins_only');
  is_deeply($param->{choices}, [qw(admins_only end_users disabled)], 'allowed choices');
  is($param->{checker}->('end_users', $param), '', 'accepts a valid choice');
  isnt($param->{checker}->('everyone', $param), '', 'rejects an unknown choice');

  my $panels = {panel_modules => {}};
  $Ext->config_add_panels($panels);
  is($panels->{panel_modules}{Donation}, "${Ext}::Config", 'registers Donation panel');
};

subtest 'settings are registered with the 5.2 API' => sub {
  @settings = ();
  $Ext->install_before_final_checks({silent => 1});
  is_deeply(
    \@settings,
    [
      ['donate_banner_pref', ['next_upgrade', 'specific_date', 'never'], 'next_upgrade', undef, undef, 1],
      ['donate_banner_last_version', [], '0.0', undef, undef, 1],
      ['donate_banner_reminder_date', [], '1970-01-01', undef, undef, 1],
    ],
    'registers the three settings using positional arguments'
  );
};

subtest 'filesystem and settings hook' => sub {
  my %files;
  $Ext->install_filesystem({files => \%files});
  is_deeply(\%files, {
    'extensions/BugzillaDonationBanner/bin/donate.cgi' => {perms => 0755},
  }, 'registers the CGI with executable permissions');

  my %skip = (other_extension_setting => 1);
  $Ext->user_preferences_settings({skip_settings => \%skip});
  is_deeply(\%skip, {
    other_extension_setting       => 1,
    donate_banner_pref            => 1,
    donate_banner_last_version    => 1,
    donate_banner_reminder_date   => 1,
  }, 'hides only the extension settings');
};

subtest 'template and preferences hooks' => sub {
  my $vars = {};
  $Ext->template_before_process({file => 'index.html.tmpl', vars => $vars});
  is($vars->{donation}, $donation, 'provides banner data on the home page');

  $vars = {preserved => 1};
  $Ext->template_before_process({file => 'bug/show.html.tmpl', vars => $vars});
  is_deeply($vars, {preserved => 1}, 'leaves other templates alone');

  my $handled = 0;
  $Ext->user_preferences({
    current_tab  => 'account',
    vars         => $vars,
    handled      => \$handled,
    save_changes => 0,
  });
  is($handled, 0, 'ignores other preferences tabs');

  $vars = {};
  $Ext->user_preferences({
    current_tab  => 'donate',
    vars         => $vars,
    handled      => \$handled,
    save_changes => 0,
  });
  is($handled, 1, 'handles the Donate tab');
  is($vars->{donation}, $donation, 'provides banner data');
  is($vars->{today}, '2026-11-01', 'provides the current date');

  $cgi->{params} = {
    donate_banner_pref => 'specific_date',
    donate_banner_reminder_date => '2030-05-17',
  };
  $Ext->user_preferences({
    current_tab  => 'donate',
    vars         => $vars,
    handled      => \$handled,
    save_changes => 1,
  });
  is_deeply($main::saved, ['specific_date', '2030-05-17'], 'saves preference and date');
  ok($vars->{changes_saved}, 'reports saved changes');
};

done_testing;

package Local::User;

sub settings { return $_[0]->{settings} }
sub setting { return 'next_upgrade' }

package Local::CGI;

sub param { return $_[0]->{params}{$_[1]} }
