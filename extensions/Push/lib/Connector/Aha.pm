# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::Aha;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Bug;
use Bugzilla::Attachment;
use Bugzilla::BugUrl::Aha;

use DateTime;
use JSON 'decode_json', 'encode_json';
use LWP::UserAgent;

BEGIN {
    unless (LWP::UserAgent->can("put")) {
        *LWP::UserAgent::put = sub {
            require HTTP::Request::Common;
            my($self, @parameters) = @_;
            my @suff = $self->_process_colonic_headers(\@parameters, (ref($parameters[1]) ? 2 : 1));
            return $self->request( HTTP::Request::Common::PUT( @parameters ), @suff );
        };
    }
}

sub options {
    return (
        {
            name     => 'account_domain',
            label    => 'Account domain for Aha',
            type     => 'string',
            default  => 'bugzilla.aha.io',
            required => 1,
        },
        {
            name     => 'account_realm',
            label    => 'Aha! auth realm',
            type     => 'string',
            default  => 'Aha! API',
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
    );
}

sub stop {
    my ($self) = @_;
}

sub should_send {
    my ($self, $message) = @_;

    if ($message->routing_key =~ /^bug\.modify:.*\bbug_status\b/) {
        my $payload = $message->payload_decoded();
        my $target  = $payload->{event}->{target};
        my $bug     = $payload->{$target};

        return $bug->{status}{name} eq 'RESOLVED' && $bug->{resolution} eq 'FIXED';
    }
    else {
        # We're not interested in the message.
        return 0;
    }
}

sub _user_agent {
    my ($self) = @_;

    my $ua = LWP::UserAgent->new(agent => 'Bugzilla');
    $ua->timeout(10);
    $ua->protocols_allowed(['http', 'https']);
    if (my $proxy_url = Bugzilla->params->{proxy_url}) {
        $ua->proxy(['http', 'https'], $proxy_url);
    }
    else {
        $ua->env_proxy();
    }

    $ua->credentials($self->config->{account_domain} . ":443",
                     $self->config->{account_realm},
                     $self->config->{username},
                     $self->config->{password});
    return $ua;
}

sub _aha_uri {
    my ($self, $path) = @_;

    return URI->new("https://" . $self->config->{account_domain} . "/" . $path);
}

sub _aha_feature_uri {
    my ($self, $feature_id) = @_;

    return $self->_aha_uri("api/v1/features/$feature_id");
}

sub _aha_update_feature {
    my ($self, $feature_id, $workflow_status) = @_;
    my $feature_uri = $self->_aha_feature_uri($feature_id);
    my $ua          = $self->_user_agent;
    my $content     = encode_json({ workflow_status => $workflow_status });
    my $resp        = $ua->put($feature_uri, 'Content-Type' => 'application/json', Content => $content);

    if ($resp->code != 200) {
        die "Expected HTTP 200 resposne, got " . $resp->code;
    }
}

sub _aha_get_feature {
    my ($self, $feature_id) = @_;
    my $feature_uri = $self->_aha_feature_uri($feature_id);
    my $resp        = $self->_user_agent->get($feature_uri);

    if ($resp->code == 200) {
        my $result = eval { decode_json($resp->content) };
        if ($@) {
            die "Unable to parse JSON";
        }
        return $result;
    }
    else {
        die "Expected HTTP 200 resposne, got " . $resp->code;
    }
}

sub send {
    my ($self, $message) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    eval {
        my $payload = $message->payload_decoded();
        my $target  = $payload->{event}->{target};
        my $bug     = Bugzilla::Bug->check($payload->{$target}->{id});
        foreach my $see_also (@{ $bug->see_also }) {
            if ($see_also->isa('Bugzilla::BugUrl::Aha')) {
                my $feature_id = $see_also->get_feature_id;
                my $feature = $self->_aha_get_feature($feature_id);
                if ($feature->{error}) {
                    next;
                }

                unless (lc($feature->{feature}{workflow_status}{name}) eq 'shipped') {
                    $self->_aha_update_feature($feature_id, "Ready to ship");
                }
            }
        }
    };
    if ($@) {
        return (PUSH_RESULT_TRANSIENT, clean_error($@));
    }

    return PUSH_RESULT_OK;
}


1;
