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
use Bugzilla::Logging;
use Bugzilla::Constants qw( ERROR_MODE_DIE );
use Bugzilla::Mailer qw( MessageToMTA );
use Bugzilla::User ();
use Bugzilla::Util qw( html_quote remote_ip );
use JSON::MaybeXS qw( decode_json encode_json );
use LWP::UserAgent ();
use Try::Tiny qw( try catch );

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

        my $notification_type = $notification->{notificationType} // '';
        if ( $notification_type eq '' ) {
            my $keys = join ', ', keys %$notification;
            WARN("No notificationType in notification (keys: $keys)");
        }
        if ( $notification_type eq 'Bounce' ) {
            process_bounce($notification);
        }
        elsif ( $notification_type eq 'Complaint' ) {
            process_complaint($notification);
        }
        else {
            WARN("Unsupported notification-type: $notification_type");
            respond( 200 => 'OK' );
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

sub process_bounce {
    my ($notification) = @_;
    my $type = $notification->{bounce}->{bounceType};

    if ( $type eq 'Transient' ) {

        # just log transient bounces
        foreach my $recipient ( @{ $notification->{bounce}->{bouncedRecipients} } ) {
            my $address = $recipient->{emailAddress};
            Bugzilla->audit("transient bounce for <$address>");
        }
    }

    elsif ( $type eq 'Permanent' ) {

        # disable each account that is permanently bouncing
        foreach my $recipient ( @{ $notification->{bounce}->{bouncedRecipients} } ) {
            my $address = $recipient->{emailAddress};
            my $reason
                = sprintf( '(%s) %s', $recipient->{action} // 'error', $recipient->{diagnosticCode} // 'unknown' );

            my $user = Bugzilla::User->new( { name => $address, cache => 1 } );
            if ($user) {

                # never auto-disable admin accounts
                if ( $user->in_group('admin') ) {
                    Bugzilla->audit("ignoring permanent bounce for admin <$address>: $reason");
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
                    Bugzilla->audit(
                        "permanent bounce for <$address> disabled userid-" . $user->id . ": $reason" );
                }
            }

            else {
                Bugzilla->audit("permanent bounce for <$address> has no user: $reason");
            }
        }
    }

    else {
        WARN("Unsupported bounce type: $type\n");
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
