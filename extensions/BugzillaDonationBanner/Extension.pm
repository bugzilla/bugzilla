# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugzillaDonationBanner;

use 5.14.0;
use strict;
use warnings;
use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Install::Filesystem;
use Bugzilla::User::Setting qw(add_setting);
use Bugzilla::Extension::BugzillaDonationBanner::Donation;

our $VERSION = '1.0';

sub config_add_panels {
  my ($self, $args) = @_;
  $args->{panel_modules}->{Donation}
    = 'Bugzilla::Extension::BugzillaDonationBanner::Config';
}

sub install_before_final_checks {
  my ($self, $args) = @_;
  my $silent = $args->{silent};

  add_setting('donate_banner_pref', ['next_upgrade', 'specific_date', 'never'],
    'next_upgrade', undef, undef, $silent);
  add_setting('donate_banner_last_version',  [], '0.0',        undef, undef, $silent);
  add_setting('donate_banner_reminder_date', [], '1970-01-01', undef, undef, $silent);
}

sub install_filesystem {
  my ($self, $args) = @_;
  my $files = $args->{files};
  my $extension_dir = bz_locations()->{extensionsdir} . '/'
    . __PACKAGE__->NAME;

  $files->{"$extension_dir/bin/donate.cgi"}
    = {perms => Bugzilla::Install::Filesystem::WS_EXECUTE};
}

sub template_before_process {
  my ($self, $args) = @_;
  my ($file, $vars) = @$args{qw(file vars)};

  if ($file =~ m{(?:^|/)index\.html\.tmpl$}) {
    $vars->{donation}
      = Bugzilla::Extension::BugzillaDonationBanner::Donation::get_banner();
  }
}

sub user_preferences_settings {
  my ($self, $args) = @_;
  my $skip_settings = $args->{skip_settings};
  $skip_settings->{donate_banner_pref} = 1;
  $skip_settings->{donate_banner_last_version} = 1;
  $skip_settings->{donate_banner_reminder_date} = 1;
}

sub user_preferences {
  my ($self, $args) = @_;
  return unless $args->{current_tab} eq 'donate';

  my $vars = $args->{vars};
  my $user = Bugzilla->user;
  my $cgi = Bugzilla->cgi;

  if ($args->{save_changes}) {
    my $pref = $cgi->param('donate_banner_pref') || 'next_upgrade';
    my $date = $cgi->param('donate_banner_reminder_date') || '';
    Bugzilla::Extension::BugzillaDonationBanner::Donation::save_preference(
      $pref, $date);
    $vars->{changes_saved} = 1;
  }

  $vars->{settings} = $user->settings;
  $vars->{donation}
    = Bugzilla::Extension::BugzillaDonationBanner::Donation::get_banner(1);
  $vars->{donate_pref} = $user->setting('donate_banner_pref');
  $vars->{today}
    = Bugzilla::Extension::BugzillaDonationBanner::Donation::today();
  my $reminder_date = $user->setting('donate_banner_reminder_date');
  $vars->{reminder_date}
    = !$reminder_date || $reminder_date eq '1970-01-01'
    ? $vars->{today}
    : $reminder_date;
  ${$args->{handled}} = 1;
}

__PACKAGE__->NAME;
