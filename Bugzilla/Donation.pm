# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Donation;

use 5.14.0;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Token qw(issue_session_token);

use DateTime;

use constant BANNER_URL => 'https://bugzilla.org/donate';
use constant BANNER_MESSAGES => (
  'Help us make Bugzilla better more often.',
  'A small donation helps keep Bugzilla moving forward.',
  'Support the people who keep Bugzilla running.',
  'Even a little funding helps Bugzilla improve more quickly.',
  'If Bugzilla helps your team, consider helping Bugzilla too.',
);

sub get_banner {
  my $user = Bugzilla->user;
  return undef if !$user->id;

  my $visibility = Bugzilla->params->{'donation_banner_visibility'} || 'admins_only';
  return undef if $visibility eq 'disabled';
  return undef if $visibility eq 'admins_only' && !$user->in_group('admin');

  my $settings = $user->settings;
  my $pref = $settings->{'donate_banner_pref'}->{'value'};
  my $last_version = $settings->{'donate_banner_last_version'}->{'value'} || '0';
  my $next_date = $settings->{'donate_banner_reminder_date'}->{'value'} || '1970-01-01';
  my $current_version = BUGZILLA_VERSION;

  my $show;
  my $show_thanks = 0;
  if ($pref eq 'next_upgrade') {
    $show = ($last_version ne $current_version);
    $show_thanks = $show && $user->in_group('admin') && $last_version ne '0';
  }
  elsif ($pref eq 'specific_date') {
    my $today = DateTime->now(time_zone => Bugzilla->local_timezone)->ymd;
    $show = ($next_date le $today);
  }
  else {
    $show = 0;
  }

  return undef if !$show;

  my @messages = BANNER_MESSAGES;
  my $message = $messages[int(rand(@messages))];

  my $data = {
    url            => BANNER_URL,
    message        => $message,
    show_thanks    => $show_thanks,
    visibility     => $visibility,
    settings_link  => 'editparams.cgi?section=donation#donation_banner_visibility_desc',
    token          => issue_session_token('edit_user_prefs'),
  };

  if ($visibility eq 'admins_only') {
    $data->{'visibility_note'}
      = 'This message is only shown to logged-in users with admin privs.';
  }
  elsif ($user->in_group('admin')) {
    $data->{'visibility_note'}
      = 'This message is visible to all logged-in users.';
  }

  return $data;
}

sub set_banner_preference {
  my ($action) = @_;
  my $user = Bugzilla->user;
  my $settings = $user->settings;

  my $pref_setting = $settings->{'donate_banner_pref'};
  my $date_setting = $settings->{'donate_banner_reminder_date'};
  my $version_setting = $settings->{'donate_banner_last_version'};
  my $current_version = BUGZILLA_VERSION;

  if ($action eq 'next_upgrade') {
    $pref_setting->set('next_upgrade');
    $version_setting->set($current_version);
    return 'index.cgi';
  }
  if ($action eq 'week' || $action eq 'month') {
    my $days = $action eq 'week' ? 7 : 30;
    my $dt = DateTime->now(time_zone => Bugzilla->local_timezone);
    $dt->add(days => $days);
    $pref_setting->set('specific_date');
    $date_setting->set($dt->ymd);
    $version_setting->set($current_version);
    return 'index.cgi';
  }
  if ($action eq 'never') {
    $pref_setting->set('never');
    $version_setting->set($current_version);
    return 'index.cgi';
  }
  if ($action eq 'date') {
    return 'userprefs.cgi?tab=donate';
  }

  return 'index.cgi';
}

1;

__END__

=head1 NAME

Bugzilla::Donation - Donation banner helpers

=head1 METHODS

=head2 get_banner

Builds and returns donation banner data for the current user when the banner
should be shown. Returns C<undef> when the user is not eligible or has deferred
the banner.

=head2 set_banner_preference

Applies the user's donation banner action (for example C<week>, C<month>,
C<next_upgrade>, C<never>, or C<date>) and returns the redirect target.

=cut