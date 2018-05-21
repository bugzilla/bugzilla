#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(.. ../lib ../local/lib/perl5);

use Bugzilla ();
use Bugzilla::Constants qw(ERROR_MODE_DIE);
use Bugzilla::Logging;
use Bugzilla::Mailer qw(MessageToMTA);
use Bugzilla::User ();
use Bugzilla::Util qw(html_quote remote_ip);
use JSON::MaybeXS qw(decode_json);
use LWP::UserAgent ();
use Try::Tiny qw(catch try);

Bugzilla->error_mode(ERROR_MODE_DIE);
try {
    main();
}
catch {
    FATAL("Fatal error: $_");
    respond( 500 => 'Internal Server Error' );
};

sub main {
    my $message = decode_json_wrapper( Bugzilla->cgi->param('POSTDATA') ) // return;
    my $message_type = $ENV{HTTP_X_AMZ_SNS_MESSAGE_TYPE} // '(missing)';

    if ( $message_type eq 'SubscriptionConfirmation' ) {
        confirm_subscription($message);
    }

    elsif ( $message_type eq 'Notification' ) {
        my $notification = decode_json_wrapper( $message->{Message} ) // return;
        unless (
            # https://docs.aws.amazon.com/ses/latest/DeveloperGuide/event-publishing-retrieving-sns-contents.html
            handle_notification( $notification, 'eventType' )

            # https://docs.aws.amazon.com/ses/latest/DeveloperGuide/notification-contents.html
            || handle_notification( $notification, 'notificationType' )
            )
        {
            WARN('Failed to find notification type');
            respond( 400 => 'Bad Request' );
        }
    }

    else {
        WARN("Unsupported message-type: $message_type");
        respond( 200 => 'OK' );
    }
}

sub confirm_subscription {
    my ($message) = @_;

    my $subscribe_url = $message->{SubscribeURL};
    if ( !$subscribe_url ) {
        WARN('Bad SubscriptionConfirmation request: missing SubscribeURL');
        respond( 400 => 'Bad Request' );
        return;
    }

    my $ua  = ua();
    my $res = $ua->get( $message->{SubscribeURL} );
    if ( !$res->is_success ) {
        WARN( 'Bad response from SubscribeURL: ' . $res->status_line );
        respond( 400 => 'Bad Request' );
        return;
    }

    respond( 200 => 'OK' );
}

sub handle_notification {
    my ( $notification, $type_field ) = @_;

    if ( !exists $notification->{$type_field} ) {
        return 0;
    }
    my $type = $notification->{$type_field};

    if ( $type eq 'Bounce' ) {
        process_bounce($notification);
    }
    elsif ( $type eq 'Complaint' ) {
        process_complaint($notification);
    }
    else {
        WARN("Unsupported notification-type: $type");
        respond( 200 => 'OK' );
    }
    return 1;
}

sub process_bounce {
    my ($notification) = @_;

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

    respond( 200 => 'OK' );
}

sub process_complaint {

    # email notification to bugzilla admin
    my ($notification) = @_;
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

    respond( 200 => 'OK' );
}

sub respond {
    my ( $code, $message ) = @_;
    print Bugzilla->cgi->header( -status => "$code $message" );

    # apache will generate non-200 response pages for us
    say html_quote($message) if $code == 200;
}

sub decode_json_wrapper {
    my ($json) = @_;
    my $result;
    if ( !defined $json ) {
        WARN( 'Missing JSON from ' . remote_ip() );
        respond( 400 => 'Bad Request' );
        return undef;
    }
    my $ok = try {
        $result = decode_json($json);
    }
    catch {
        WARN( 'Malformed JSON from ' . remote_ip() );
        respond( 400 => 'Bad Request' );
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
