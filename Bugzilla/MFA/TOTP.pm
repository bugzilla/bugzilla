# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::MFA::TOTP;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::MFA';

use Auth::GoogleAuth;
use Bugzilla::Error;
use Bugzilla::Token qw( issue_session_token );
use Bugzilla::Util qw( template_var generate_random_password );
use GD::Barcode::QRcode;
use MIME::Base64 qw( encode_base64 );

sub can_verify_inline {
  return 1;
}

sub _auth {
  my ($self) = @_;
  return Auth::GoogleAuth->new({
    secret => $self->property_get('secret') // $self->property_get('secret.temp'),
    issuer => template_var('terms')->{BugzillaTitle},
    key_id => $self->{user}->login,
  });
}

sub enroll_api {
  my ($self) = @_;

  # create a new secret for the user
  # store it in secret.temp to avoid overwriting a valid secret
  $self->property_set('secret.temp', generate_random_password(16));

  # build the qr code
  my $auth = $self->_auth();
  my $otpauth = $auth->qr_code(undef, undef, undef, 1);
  my $png = GD::Barcode::QRcode->new($otpauth, {Version => 10, ModuleSize => 3})
    ->plot()->png();
  return {png => encode_base64($png), secret32 => $auth->secret32};
}

sub enrolled {
  my ($self) = @_;

  # make the temporary secret permanent
  $self->property_set('secret', $self->property_get('secret.temp'));
  $self->property_delete('secret.temp');
}

sub prompt {
  my ($self, $vars) = @_;
  my $template = Bugzilla->template;

  print Bugzilla->cgi->header();
  $template->process('mfa/totp/verify.html.tmpl', $vars)
    || ThrowTemplateError($template->error());
}

sub check {
  my ($self, $params) = @_;
  my $code = $params->{code};
  return if $self->_auth()->verify($code, 1);

  if ($params->{mfa_action} && $params->{mfa_action} eq 'enable') {
    ThrowUserError('mfa_totp_bad_enrollment_code');
  }
  else {
    ThrowUserError('mfa_bad_code');
  }
}

1;
