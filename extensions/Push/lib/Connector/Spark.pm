# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::Spark;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Bug;
use Bugzilla::Attachment;
use Bugzilla::Util ();

use JSON qw(decode_json encode_json);
use LWP::UserAgent;
use List::MoreUtils qw(any);

sub options {
  return (
    {
      name     => 'spark_endpoint',
      label    => 'Spark API Endpoint',
      type     => 'string',
      default  => 'https://api.ciscospark.com/v1',
      required => 1,
    },
    {
      name     => 'spark_room_id',
      label    => 'Spark Room ID',
      type     => 'string',
      default  => 'bugzilla',
      required => 1,
    },
    {
      name     => 'spark_api_key',
      label    => 'Spark API Key',
      type     => 'string',
      default  => '',
      required => 1,
    },
  );
}

sub stop {
  my ($self) = @_;
}

sub should_send {
  my ($self, $message) = @_;

  my $data = $message->payload_decoded;
  my $bug_data = $self->_get_bug_data($data) || return 0;

  # Send if bug has cisco-spark keyword
  my $bug = Bugzilla::Bug->new({id => $bug_data->{id}, cache => 1});
  return 0 unless $bug->has_keyword('cisco-spark');

  if ($message->routing_key eq 'bug.create') {
    return 1;
  }
  else {
    foreach my $change (@{$data->{event}->{changes}}) {

      # send status and resolution updates
      return 1
        if $change->{field} eq 'bug_status' || $change->{field} eq 'resolution';

      # also send if the right keyword has been added to this bug
      if ($change->{field} eq 'keywords' && $change->{added}) {
        my @added = split(/, /, $change->{added});
        return 1 if any { $_ eq 'cisco-spark' } @added;
      }
    }
  }

  # and nothing else
  return 0;
}

sub send {
  my ($self, $message) = @_;

  eval {
    my $data     = $message->payload_decoded();
    my $bug_data = $self->_get_bug_data($data);
    my $bug      = Bugzilla::Bug->new({id => $bug_data->{id}, cache => 1});

    my $text = "Bug " . $bug->id . " - " . $bug->short_desc . "\n";
    if ($message->routing_key eq 'bug.create') {
      $text = "New " . $text;
    }
    else {
      foreach my $change (@{$data->{event}->{changes}}) {
        if ($change->{field} eq 'bug_status') {
          $text
            .= "Status changed: " . $change->{removed} . " -> " . $change->{added} . "\n";
        }
        if ($change->{field} eq 'resolution') {
          $text
            .= "Resolution changed: "
            . ($change->{removed} ? $change->{removed} . " -> " : "")
            . $change->{added} . "\n";
        }
      }
    }
    $text .= Bugzilla->localconfig->{urlbase} . "show_bug.cgi?id=" . $bug->id;

    my $room_id     = $self->config->{spark_room_id};
    my $message_uri = $self->_spark_uri('messages');

    my $json_data = {roomId => $room_id, text => $text};

    my $headers = HTTP::Headers->new(Content_Type => 'application/json');
    my $request
      = HTTP::Request->new('POST', $message_uri, $headers, encode_json($json_data));
    my $resp = $self->_user_agent->request($request);

    if ($resp->code != 200) {
      die "Expected HTTP 200 response, got " . $resp->code;
    }
  };
  if ($@) {
    return (PUSH_RESULT_TRANSIENT, clean_error($@));
  }

  return PUSH_RESULT_OK;
}

# Private methods

sub _get_bug_data {
  my ($self, $data) = @_;
  my $target = $data->{event}->{target};
  if ($target eq 'bug') {
    return $data->{bug};
  }
  elsif (exists $data->{$target}->{bug}) {
    return $data->{$target}->{bug};
  }
  else {
    return;
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

  $ua->default_header(
    'Authorization' => 'Bearer ' . $self->config->{spark_api_key});

  return $ua;
}

sub _spark_uri {
  my ($self, $path) = @_;
  return URI->new($self->config->{spark_endpoint} . "/" . $path);
}

1;
