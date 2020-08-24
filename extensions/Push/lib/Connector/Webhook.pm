# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::Webhook;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Attachment;
use Bugzilla::Extension::Webhooks::Webhook;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Util ();

use JSON qw(decode_json encode_json);
use LWP::UserAgent;
use List::MoreUtils qw(any);
use Try::Tiny;

sub new {
  my ($class,$webhook_id) = @_;
  my $self = {};
  bless($self, $class);
  $self->{name} = 'Webhook_' . $webhook_id;
  $self->{webhook_id} = $webhook_id;
  $self->init();
  return $self;
}

sub load_config {
  my ($self) = @_;
  my $config
    = Bugzilla::Extension::Push::Config->new($self->name, $self->options);
  $config->option('enabled')->{'default'} = 'Enabled';
  $config->load();
  $self->{config} = $config;
}

sub save {
  my ($self) = @_;
  my $dbh  = Bugzilla->dbh;
  my $push = Bugzilla->push_ext;
  $dbh->bz_start_transaction();
  $self->config->update();
  $push->set_config_last_modified();
  $dbh->bz_commit_transaction();
}

sub should_send {
  my ($self, $message) = @_;

  return 0 unless Bugzilla->params->{webhooks_enabled};

  my $webhook   = Bugzilla::Extension::Webhooks::Webhook->new($self->{webhook_id});
  my $event     = $webhook->event;
  my $product   = $webhook->product_name;
  my $component = $webhook->component_name ? $webhook->component_name : 'any';

  my $data     = $message->payload_decoded;
  my $bug_data = $self->_get_bug_data($data) || return 0;

  my $bug = Bugzilla::Bug->new({id => $bug_data->{id}, cache => 1});

  if ($product eq $bug->product
      && ($component eq $bug->component || $component eq 'any'))
  {
    if ($event =~ /create/ && $message->routing_key eq 'bug.create') {
      return 1;
    }elsif ($event =~ /change/ && $message->routing_key =~ /\Qbug.modify\E/) {
      return 1;
    }
  }

  return 0;
}

sub send {
  my ($self, $message) = @_;

  try {
    my $webhook = Bugzilla::Extension::Webhooks::Webhook->new($self->{webhook_id});

    my $payload              = $message->payload_decoded;
    $payload->{webhook_name} = $webhook->name;
    $payload->{webhook_id}   = $webhook->id;

    my $bug_data   = $self->_get_bug_data($payload);
    my $is_private = $bug_data->{is_private};
    if ($is_private){
      delete @{$payload}{bug};
      if($payload->{event}->{action} eq 'modify'){
        delete @{$payload->{event}}{changes};
      }
      $payload->{bug}->{id}       = $bug_data->{id};
      $payload->{bug}->{is_private} = $is_private;
    }
    delete @{$payload->{event}}{qw(routing_key change_set target)};

    my $headers = HTTP::Headers->new(Content_Type => 'application/json');
    my $request
      = HTTP::Request->new('POST', $webhook->url, $headers, encode_json($payload));
    my $resp = $self->_user_agent->request($request);
    if ($resp->code != 200) {
      die "Expected HTTP 200 response, got " . $resp->code;
    }else{
      return PUSH_RESULT_OK;
    }
  }
  catch{
    return (PUSH_RESULT_TRANSIENT, clean_error($_));
  };

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

  return $ua;
}

1;
