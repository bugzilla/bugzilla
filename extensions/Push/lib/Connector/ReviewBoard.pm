# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::ReviewBoard;

use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Bug;
use Bugzilla::Attachment;
use Bugzilla::Extension::Push::Connector::ReviewBoard::Client;

use JSON 'decode_json';
use DateTime;
use Scalar::Util 'blessed';

use constant RB_CONTENT_TYPE => 'text/x-review-board-request';

sub client {
    my $self = shift;

    $self->{client} //= Bugzilla::Extension::Push::Connector::ReviewBoard::Client->new(
        base_uri => $self->config->{base_uri},
        username => $self->config->{username},
        password => $self->config->{password},
        $self->config->{proxy} ? (proxy => $self->config->{proxy}) : (),
    );

    return $self->{client};
}

sub options {
    return (
        {
            name     => 'base_uri',
            label    => 'Base URI for ReviewBoard',
            type     => 'string',
            default  => 'https://reviewboard.allizom.org',
            required => 1,
        },
        {
            name     => 'username',
            label    => 'Username',
            type     => 'string',
            default  => 'guest',
            required => 1,
        },
        {
            name     => 'password',
            label    => 'Password',
            type     => 'password',
            default  => 'guest',
            required => 1,
        },
        {
            name  => 'proxy',
            label => 'Proxy',
            type  => 'string',
        },
    );
}

sub stop {
    my ($self) = @_;
}

sub should_send {
    my ($self, $message) = @_;

    if ($message->routing_key =~ /^(?:attachment|bug)\.modify:.*\bis_private\b/) {
        my $payload = $message->payload_decoded();
        my $target  = $payload->{event}->{target};

        if ($target ne 'bug' && exists $payload->{$target}->{bug}) {
            return 0 if $payload->{$target}->{bug}->{is_private};
            return 0 if $payload->{$target}->{content_type} ne RB_CONTENT_TYPE;
        }

        return $payload->{$target}->{is_private} ? 1 : 0;
    }
    else {
        # We're not interested in the message.
        return 0;
    }
}

sub send {
    my ($self, $message) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    eval {
        my $payload = $message->payload_decoded();
        my $target  = $payload->{event}->{target};

        if (my $method = $self->can("_process_$target")) {
            $self->$method($payload->{$target});
        }
    };
    if ($@) {
        return (PUSH_RESULT_TRANSIENT, clean_error($@));
    }

    return PUSH_RESULT_OK;
}

sub _process_attachment {
    my ($self, $payload_target) = @_;
    my $logger     = Bugzilla->push_ext->logger;
    my $attachment = blessed($payload_target)
                   ? $payload_target
                   : Bugzilla::Attachment->new({ id => $payload_target->{id}, cache => 1 });

    if ($attachment) {
        my $content    = $attachment->data;
        my $base_uri   = quotemeta($self->config->{base_uri});
        if (my ($id) = $content =~ m|$base_uri/r/([0-9]+)|) {
            my $resp    = $self->client->review_request->delete($id);
            my $content = $resp->decoded_content;
            my $status  = $resp->code;
            my $result  = $content && decode_json($content) ;

            if ($status == 204) {
                # Success, review request deleted!
                $logger->debug("Deleted review request $id");
            }
            elsif ($status == 404) {
                # API error 100 - Does Not Exist
                $logger->debug("Does Not Exist: Review Request $id does not exist");
            }
            elsif ($status == 403) {
                # API error 101 - Permission Denied
                $logger->error("Permission Denied: ReviewBoard Push Connector may be misconfigured");
                die $result->{err}{msg};
            }
            elsif ($status == 401) {
                # API error 103 - Not logged in
                $logger->error("Not logged in: ReviewBoard Push Connector may be misconfigured");
                die $result->{err}{msg};
            }
            else {
                if ($result) {
                    my $code = $result->{err}{code};
                    my $msg  = $result->{err}{msg};
                    $logger->error("Unexpected API Error: ($code) $msg");
                    die $msg;
                }
                else {
                    $logger->error("Unexpected HTTP Response $status");
                    die "HTTP Status: $status";
                }
            }
        }
        else {
            $logger->error("Cannot find link: ReviewBoard Push Connector may be misconfigured");
            die "Unable to find link in $content";
        }
    }
    else {
        $logger->error("Cannot find attachment with id = $payload_target->{id}");
    }
}

sub _process_bug {
    my ($self, $payload_target) = @_;

    Bugzilla->set_user(Bugzilla::User->super_user);
    my $bug = Bugzilla::Bug->new({ id => $payload_target->{id}, cache => 1 });
    my @attachments = @{ $bug->attachments };
    Bugzilla->logout;

    foreach my $attachment (@attachments) {
        next if $attachment->contenttype ne RB_CONTENT_TYPE;
        $self->_process_attachment($attachment);
    }
}

1;
