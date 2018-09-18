package Bugzilla::Quantum::SES;
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use Mojo::Base qw( Mojolicious::Controller );

use Bugzilla::Constants qw(ERROR_MODE_DIE);
use Bugzilla::Logging;
use Bugzilla::Mailer qw(MessageToMTA);
use Bugzilla::User ();
use Bugzilla::Util qw(html_quote remote_ip);
use JSON::MaybeXS qw(decode_json);
use LWP::UserAgent ();
use Try::Tiny qw(catch try);

use Types::Standard qw( :all );
use Type::Utils;
use Type::Params qw( compile );

my $Invocant = class_type { class => __PACKAGE__ };

sub main {
    my ($self) = @_;
    try {
        $self->_main;
    }
    catch {
        FATAL("Error in SES Handler: ", $_);
        $self->_respond( 400 => 'Bad Request' );
    };
}

sub _main {
    my ($self) = @_;
    Bugzilla->error_mode(ERROR_MODE_DIE);
    my $message = $self->_decode_json_wrapper( $self->req->body ) // return;
    my $message_type = $self->req->headers->header('X-Amz-SNS-Message-Type') // '(missing)';

    if ( $message_type eq 'SubscriptionConfirmation' ) {
        $self->_confirm_subscription($message);
    }

    elsif ( $message_type eq 'Notification' ) {
        my $notification = $self->_decode_json_wrapper( $message->{Message} ) // return;
        unless (
            # https://docs.aws.amazon.com/ses/latest/DeveloperGuide/event-publishing-retrieving-sns-contents.html
            $self->_handle_notification( $notification, 'eventType' )

            # https://docs.aws.amazon.com/ses/latest/DeveloperGuide/notification-contents.html
            || $self->_handle_notification( $notification, 'notificationType' )
            )
        {
            WARN('Failed to find notification type');
            $self->_respond( 400 => 'Bad Request' );
        }
    }

    else {
        WARN("Unsupported message-type: $message_type");
        $self->_respond( 200 => 'OK' );
    }
}

sub _confirm_subscription {
    state $check = compile($Invocant, Dict[SubscribeURL => Str, slurpy Any]);
    my ($self, $message) = $check->(@_);

    my $subscribe_url = $message->{SubscribeURL};
    if ( !$subscribe_url ) {
        WARN('Bad SubscriptionConfirmation request: missing SubscribeURL');
        $self->_respond( 400 => 'Bad Request' );
        return;
    }

    my $ua  = ua();
    my $res = $ua->get( $message->{SubscribeURL} );
    if ( !$res->is_success ) {
        WARN( 'Bad response from SubscribeURL: ' . $res->status_line );
        $self->_respond( 400 => 'Bad Request' );
        return;
    }

    $self->_respond( 200 => 'OK' );
}

my $NotificationType = Enum [qw( Bounce Complaint )];
my $TypeField        = Enum [qw(eventType notificationType)];
my $Notification = Dict [
    eventType        => Optional [$NotificationType],
    notificationType => Optional [$NotificationType],
    slurpy Any,
];

sub _handle_notification {
    state $check = compile($Invocant, $Notification, $TypeField );
    my ( $self, $notification, $type_field ) = $check->(@_);

    if ( !exists $notification->{$type_field} ) {
        return 0;
    }
    my $type = $notification->{$type_field};

    if ( $type eq 'Bounce' ) {
        $self->_process_bounce($notification);
    }
    elsif ( $type eq 'Complaint' ) {
        $self->_process_complaint($notification);
    }
    else {
        WARN("Unsupported notification-type: $type");
        $self->_respond( 200 => 'OK' );
    }
    return 1;
}

my $BouncedRecipients = ArrayRef[
    Dict[
       emailAddress   => Str,
       action         => Str,
       diagnosticCode => Str,
       slurpy Any,
    ],
];
my $BounceNotification = Dict [
    bounce => Dict [
        bouncedRecipients => $BouncedRecipients,
        reportingMTA      => Str,
        bounceSubType     => Str,
        bounceType        => Str,
        slurpy Any,
    ],
    slurpy Any,
];

sub _process_bounce {
    state $check = compile($Invocant, $BounceNotification);
    my ($self, $notification) = $check->(@_);

    # disable each account that is bouncing
    foreach my $recipient ( @{ $notification->{bounce}->{bouncedRecipients} } ) {
        my $address = $recipient->{emailAddress};
        my $reason = sprintf '(%s) %s', $recipient->{action} // 'error', $recipient->{diagnosticCode} // 'unknown';

        my $user = Bugzilla::User->new( { name => $address, cache => 1 } );
        if ($user) {

            # never auto-disable admin accounts
            if ( $user->in_group('admin') ) {
                Bugzilla->audit("ignoring bounce for admin <$address>: $reason");
            }

            else {
                my $template = Bugzilla->template_inner();
                my $vars     = {
                    mta => $notification->{bounce}->{reportingMTA} // 'unknown',
                    reason => $reason,
                };
                my $disable_text;
                $template->process( 'admin/users/bounce-disabled.txt.tmpl', $vars, \$disable_text )
                    || die $template->error();

                $user->set_disabledtext($disable_text);
                $user->set_disable_mail(1);
                $user->update();
                Bugzilla->audit( "bounce for <$address> disabled userid-" . $user->id . ": $reason" );
            }
        }

        else {
            Bugzilla->audit("bounce for <$address> has no user: $reason");
        }
    }

    $self->_respond( 200 => 'OK' );
}

my $ComplainedRecipients = ArrayRef[Dict[ emailAddress => Str, slurpy Any ]];
my $ComplaintNotification = Dict[
    complaint => Dict [
        complainedRecipients => $ComplainedRecipients,
        complaintFeedbackType => Str,
        slurpy Any,
    ],
    slurpy Any,
];

sub _process_complaint {
    state $check = compile($Invocant, $ComplaintNotification);
    my ($self, $notification) = $check->(@_);
    my $template       = Bugzilla->template_inner();
    my $json           = JSON::MaybeXS->new(
        pretty    => 1,
        utf8      => 1,
        canonical => 1,
    );

    foreach my $recipient ( @{ $notification->{complaint}->{complainedRecipients} } ) {
        my $reason = $notification->{complaint}->{complaintFeedbackType} // 'unknown';
        my $address = $recipient->{emailAddress};
        Bugzilla->audit("complaint for <$address> for '$reason'");
        my $vars = {
            email        => $address,
            user         => Bugzilla::User->new( { name => $address, cache => 1 } ),
            reason       => $reason,
            notification => $json->encode($notification),
        };
        my $message;
        $template->process( 'email/ses-complaint.txt.tmpl', $vars, \$message )
            || die $template->error();
        MessageToMTA($message);
    }

    $self->_respond( 200 => 'OK' );
}

sub _respond {
    my ( $self, $code, $message ) = @_;
    $self->render(text => "$message\n", status => $code);
}

sub _decode_json_wrapper {
    state $check = compile($Invocant, Str);
    my ($self, $json) = $check->(@_);
    my $result;
    my $ok = try {
        $result = decode_json($json);
    }
    catch {
        WARN( 'Malformed JSON from ' . $self->tx->remote_address );
        $self->_respond( 400 => 'Bad Request' );
        return undef;
    };
    return $ok ? $result : undef;
}

sub ua {
    my $ua = LWP::UserAgent->new();
    $ua->timeout(10);
    $ua->protocols_allowed( [ 'http', 'https' ] );
    if ( my $proxy_url = Bugzilla->params->{'proxy_url'} ) {
        $ua->proxy( [ 'http', 'https' ], $proxy_url );
    }
    else {
        $ua->env_proxy;
    }
    return $ua;
}

1;
