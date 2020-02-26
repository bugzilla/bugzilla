# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::BouncedEmails;

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Token;

sub setup_routes {
  my ($class, $r) = @_;
  $r->any('/bounced_emails/:userid')->to('BouncedEmails#view');
}

sub view {
  my ($self)     = @_;
  my $user       = $self->bugzilla->login(LOGIN_REQUIRED);
  my $other_user = Bugzilla::User->check({id => $self->param('userid')});

  unless ($user->in_group('editusers')
    || $user->in_group('disableusers')
    || $user->id == $other_user->id)
  {
    ThrowUserError('auth_failure',
      {reason => "not_visible", action => "modify", object => "user"});
  }

  if ( $self->param('enable_email')
    && $user->id == $other_user->id
    && $other_user->email_disabled)
  {
    my $token = $self->param('token');
    check_token_data($token, 'bounced_emails');

    $other_user->set_email_enabled(1);
    $other_user->update();

    return $self->redirect_to('/home');
  }

  my $token = issue_session_token('bounced_emails');
  $self->stash(
    {
      bounce_max => BOUNCE_COUNT_MAX,
      user       => $user,
      other_user => $other_user,
      token      => $token
    }
  );
  return $self->render(
    template => 'account/email/bounced-emails',
    handler  => 'bugzilla'
  );
}

1;
