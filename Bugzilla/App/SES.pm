package Bugzilla::App::SES;

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Constants qw(BOUNCE_COUNT_MAX ERROR_MODE_DIE);
use Bugzilla::Logging;
use Bugzilla::Mailer qw(MessageToMTA);
use Bugzilla::User ();
use Bugzilla::Util qw(html_quote remote_ip);
use JSON::MaybeXS qw(decode_json);
use LWP::UserAgent ();
use Try::Tiny qw(catch try);

use Type::Library -base, -declare => qw(
  Self
  Notification NotificationType TypeField
  BounceNotification BouncedRecipients
  ComplaintNotification ComplainedRecipients
);
use Type::Utils -all;
use Types::Standard -all;
use Type::Params qw(compile);

class_type Self, {class => __PACKAGE__};

declare ComplainedRecipients,
  as ArrayRef [Dict [emailAddress => Str, slurpy Any]];
declare ComplaintNotification,
  as Dict [
  complaint => Dict [
    complainedRecipients  => ComplainedRecipients,
    complaintFeedbackType => Str,
    slurpy Any,
  ],
  slurpy Any,
  ];

declare BouncedRecipients,
  as ArrayRef [
  Dict [
    emailAddress   => Str,
    action         => Optional [Str],
    diagnosticCode => Optional [Str],
    status         => Optional [Str],
    slurpy Any,
  ],
  ];
declare BounceNotification,
  as Dict [
  bounce => Dict [
    bouncedRecipients => BouncedRecipients,
    reportingMTA      => Optional [Str],
    bounceSubType     => Str,
    bounceType        => Str,
    slurpy Any,
  ],
  slurpy Any,
  ];

declare NotificationType, as Enum [qw( Bounce Complaint )];
declare TypeField,        as Enum [qw(eventType notificationType)];
declare Notification,
  as Dict [
  eventType        => Optional [NotificationType],
  notificationType => Optional [NotificationType],
  slurpy Any,
  ];

sub setup_routes {
  my ($class, $r) = @_;

  my $ses_auth = $r->under(
    '/ses' => sub {
      my ($c) = @_;
      my $lc = Bugzilla->localconfig;

      return $c->basic_auth('SES', $lc->{ses_username}, $lc->{ses_password});
    }
  );
  $ses_auth->any('/index.cgi')->to('SES#main');
}

sub main {
  my ($self) = @_;
  try {
    $self->_main;
  }
  catch {
    FATAL("Error in SES Handler: ", $_);
    $self->_respond(400 => 'Bad Request');
  };
}

sub _main {
  my ($self) = @_;
  Bugzilla->error_mode(ERROR_MODE_DIE);
  my $message      = $self->_decode_json_wrapper($self->req->body) // return;
  my $message_type = $self->req->headers->header('X-Amz-SNS-Message-Type')
    // '(missing)';

  if ($message_type eq 'SubscriptionConfirmation') {
    $self->_confirm_subscription($message);
  }

  elsif ($message_type eq 'Notification') {
    my $notification = $self->_decode_json_wrapper($message->{Message}) // return;
    unless (
# https://docs.aws.amazon.com/ses/latest/DeveloperGuide/event-publishing-retrieving-sns-contents.html
      $self->_handle_notification($notification, 'eventType')

# https://docs.aws.amazon.com/ses/latest/DeveloperGuide/notification-contents.html
      || $self->_handle_notification($notification, 'notificationType')
      )
    {
      WARN('Failed to find notification type');
      $self->_respond(400 => 'Bad Request');
    }
  }

  else {
    WARN("Unsupported message-type: $message_type");
    $self->_respond(200 => 'OK');
  }
}

sub _confirm_subscription {
  state $check = compile(Self, Dict [SubscribeURL => Str, slurpy Any]);
  my ($self, $message) = $check->(@_);

  my $subscribe_url = $message->{SubscribeURL};
  if (!$subscribe_url) {
    WARN('Bad SubscriptionConfirmation request: missing SubscribeURL');
    $self->_respond(400 => 'Bad Request');
    return;
  }

  my $ua  = ua();
  my $res = $ua->get($message->{SubscribeURL});
  if (!$res->is_success) {
    WARN('Bad response from SubscribeURL: ' . $res->status_line);
    $self->_respond(400 => 'Bad Request');
    return;
  }

  $self->_respond(200 => 'OK');
}

sub _handle_notification {
  state $check = compile(Self, Notification, TypeField);
  my ($self, $notification, $type_field) = $check->(@_);

  if (!exists $notification->{$type_field}) {
    return 0;
  }
  my $type = $notification->{$type_field};

  if ($type eq 'Bounce') {
    $self->_process_bounce($notification);
  }
  elsif ($type eq 'Complaint') {
    $self->_process_complaint($notification);
  }
  else {
    WARN("Unsupported notification-type: $type");
    $self->_respond(200 => 'OK');
  }
  return 1;
}

sub _process_bounce {
  state $check = compile(Self, BounceNotification);
  my ($self, $notification) = $check->(@_);

  # disable each account that is bouncing
  foreach my $recipient (@{$notification->{bounce}->{bouncedRecipients}}) {
    my $address = $recipient->{emailAddress};
    my $reason  = sprintf '(%s) %s', $recipient->{action} // 'error',
      $recipient->{diagnosticCode} // 'unknown';

    my $user = Bugzilla::User->new({name => $address, cache => 1});
    if ($user) {

      # never auto-disable admin accounts
      if ($user->in_group('admin')) {
        Bugzilla->audit("ignoring bounce for admin <$address>: $reason");
      }

      else {
        my $template = Bugzilla->template_inner();
        my $vars     = {
          mta    => $notification->{bounce}->{reportingMTA} // 'unknown',
          reason => $reason,
        };
        my $bounce_message;
        $template->process('admin/users/bounce-disabled.txt.tmpl',
          $vars, \$bounce_message)
          || die $template->error();

        # Increment bounce count for user
        my $bounce_count = $user->bounce_count + 1;

        # If user has not had a bounce in less than 30 days, set the bounce count to 1 instead
        my $dbh = Bugzilla->dbh;
        my ($has_recent_bounce) = $dbh->selectrow_array(
          "SELECT 1 FROM audit_log WHERE object_id = ? AND class = 'Bugzilla::User' AND field = 'bounce_message' AND ("
            . $dbh->sql_date_math('at_time', '+', 30, 'DAY')
            . ") > NOW()",
          undef, $user->id
        );
        $bounce_count = 1 if !$has_recent_bounce;

        $user->set_disable_mail(1);
        $user->set_bounce_count($bounce_count);

        # if we hit the max amount, go ahead and disabled the account
        # and an admin will need to reactivate the account.
        if ($bounce_count == BOUNCE_COUNT_MAX) {
          $user->set_disabledtext($bounce_message);
        }

        $user->update();

        # Do this outside of Object.pm as we do not want to
        # store the messages anywhere else.
        $dbh->do(
          "INSERT INTO audit_log (user_id, class, object_id, field, added, at_time)
           VALUES (?, 'Bugzilla::User', ?, 'bounce_message', ?, LOCALTIMESTAMP(0))",
          undef, $user->id, $user->id, $bounce_message
        );

        Bugzilla->audit(
          "bounce for <$address> disabled email for userid-" . $user->id . ": $reason");
      }
    }

    else {
      Bugzilla->audit("bounce for <$address> has no user: $reason");
    }
  }

  $self->_respond(200 => 'OK');
}

sub _process_complaint {
  state $check = compile(Self, ComplaintNotification);
  my ($self, $notification) = $check->(@_);
  my $template = Bugzilla->template_inner();
  my $json     = JSON::MaybeXS->new(pretty => 1, utf8 => 1, canonical => 1,);

  foreach my $recipient (@{$notification->{complaint}->{complainedRecipients}}) {
    my $reason  = $notification->{complaint}->{complaintFeedbackType} // 'unknown';
    my $address = $recipient->{emailAddress};
    Bugzilla->audit("complaint for <$address> for '$reason'");
    my $vars = {
      email        => $address,
      user         => Bugzilla::User->new({name => $address, cache => 1}),
      reason       => $reason,
      notification => $json->encode($notification),
    };
    my $message;
    $template->process('email/ses-complaint.txt.tmpl', $vars, \$message)
      || die $template->error();
    MessageToMTA($message);
  }

  $self->_respond(200 => 'OK');
}

sub _respond {
  my ($self, $code, $message) = @_;
  $self->render(text => "$message\n", status => $code);
}

sub _decode_json_wrapper {
  state $check = compile(Self, Str);
  my ($self, $json) = $check->(@_);
  my $result;
  my $ok = try {
    $result = decode_json($json);
  }
  catch {
    WARN('Malformed JSON from ' . $self->tx->remote_address);
    $self->_respond(400 => 'Bad Request');
    return undef;
  };
  return $ok ? $result : undef;
}

sub ua {
  my $ua = LWP::UserAgent->new();
  $ua->timeout(10);
  $ua->protocols_allowed(['http', 'https']);
  if (my $proxy_url = Bugzilla->params->{'proxy_url'}) {
    $ua->proxy(['http', 'https'], $proxy_url);
  }
  else {
    $ua->env_proxy;
  }
  return $ua;
}

1;
