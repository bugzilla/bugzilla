# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Webhooks;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Component;
use Bugzilla::Product;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Logging;
use Bugzilla::Extension::Webhooks::Webhook;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Util;
use Try::Tiny;

#
# installation
#

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  my $dbh = Bugzilla->dbh;
  $args->{'schema'}->{'webhooks'} = {
    FIELDS => [
      id      => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      user_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'profiles', COLUMN => 'userid', DELETE => 'CASCADE',}
      },
      name  => {TYPE    => 'VARCHAR(64)', NOTNULL => 1,},
      url   => {TYPE    => 'VARCHAR(64)', NOTNULL => 1,},
      event => {TYPE    => 'VARCHAR(64)', NOTNULL => 1,},
      product_id   => {
        TYPE       => 'INT2',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'products', COLUMN => 'id', DELETE => 'CASCADE',}
      },
      component_id => {
        TYPE       => 'INT2',
        NOTNULL    => 0,
        REFERENCES => {TABLE => 'components', COLUMN => 'id', DELETE => 'CASCADE',}
      }
    ],
    INDEXES => [
      webhooks_userid_name_idx => {FIELDS => ['user_id', 'name'], TYPE => 'UNIQUE',},
    ],
  };
}

sub db_sanitize {
  my $dbh = Bugzilla->dbh;
  print "Deleting webhooks...\n";
  $dbh->do("DELETE FROM webhooks");
}

#
# preferences
#

sub user_preferences {
  my ($self, $args) = @_;

  return unless Bugzilla->params->{webhooks_enabled}
                && Bugzilla->user->in_group(Bugzilla->params->{"webhooks_group"});
  return unless $args->{'current_tab'} eq 'webhooks';

  my $input = Bugzilla->input_params;
  my $user  = Bugzilla->user;
  my $push  = Bugzilla->push_ext;
  my $vars  = $args->{vars};

  if ($args->{'save_changes'}) {

    if ($input->{'add_webhook'}) {

      # add webhook

      my $params = {user_id => $user->id,};

      if ($input->{name} eq '') {
        ThrowUserError('webhooks_define_name');
      }
      else {
        $params->{name} = $input->{name};
      }

      if ($input->{url} eq '') {
        ThrowUserError('webhooks_define_url');
      }
      else {
        $params->{url} = $input->{url};
      }

      if ($input->{create_event} && $input->{change_event}) {
        $params->{event} = 'create,change';
      }
      elsif ($input->{create_event}) {
        $params->{event} = 'create';
      }
      elsif ($input->{change_event}) {
        $params->{event} = 'change';
      }
      else {
        ThrowUserError('webhooks_select_event');
      }

      my $product_name = $input->{add_product};
      my $product = Bugzilla::Product->check({name => $product_name, cache => 1});
      $params->{product_id} = $product->id;

      if (my $component_name = $input->{add_component}) {
        my $component = Bugzilla::Component->check({
          name => $component_name, product => $product, cache => 1});
        $params->{component_id} = $component->id;
      }

      my $new_webhook = Bugzilla::Extension::Webhooks::Webhook->create($params);

      create_push_connector($new_webhook->{id});

    }
    else {

      # remove webhook(s)

      my $ids  = ref($input->{remove}) ? $input->{remove} : [$input->{remove}];
      my $dbh  = Bugzilla->dbh;
      my $push = Bugzilla->push_ext;

      my $webhooks = Bugzilla::Extension::Webhooks::Webhook->match(
        {id => $ids, user_id => $user->id});
      $dbh->bz_start_transaction;
      foreach my $webhook (@$webhooks) {
        delete_backlog_queue($webhook->id);
        $webhook->remove_from_db();
      }
      $push->set_config_last_modified();
      $dbh->bz_commit_transaction();

      # save change(s)

      $webhooks = Bugzilla::Extension::Webhooks::Webhook->match(
        {user_id => $user->id});
      $dbh->bz_start_transaction;
      foreach my $webhook (@$webhooks) {
        my $connector = $push->connectors->by_name('Webhook_' . $webhook->id);
        my $config = $connector->config;
        my $status = trim($input->{$connector->name . ".enabled"});
        if ( $status eq 'Enabled' || $status eq 'Disabled' ){
          $config->{enabled} = $status;
          $config->update();
        }else{
          ThrowUserError('webhooks_invalid_option');
        }
      }
      $push->set_config_last_modified();
      $dbh->bz_commit_transaction();
    }

  }

  $vars->{webhooks} = [
    sort {
           $a->product_name cmp $b->product_name
        || $a->component_name cmp $b->component_name
    } @{Bugzilla::Extension::Webhooks::Webhook->match({
        user_id => $user->id,
      })
    }
  ];
  $vars->{push}           = $push;
  $vars->{connectors}     = $push->connectors;
  $vars->{webhooks_saved} = 1;

  ${$args->{handled}} = 1;
}

#
# admin
#

sub config_add_panels {
  my ($self, $args) = @_;
  my $modules = $args->{panel_modules};
  $modules->{Webhooks} = "Bugzilla::Extension::Webhooks::Config";
}

#
# templates
#

sub template_before_process {
  my ($self, $args) = @_;
  return if Bugzilla->params->{webhooks_enabled}
            && Bugzilla->user->in_group(Bugzilla->params->{"webhooks_group"});
  my ($vars, $file) = @$args{qw(vars file)};
  return unless $file eq 'account/prefs/tabs.html.tmpl';
  @{$vars->{tabs}} = grep { $_->{name} ne 'webhooks' } @{$vars->{tabs}};
}

#
# push connector
#

sub create_push_connector {
  my ($webhook_id) = @_;
  my $webhook_name = 'Webhoook_' . $webhook_id;
  my $package = "Bugzilla::Extension::Push::Connector::Webhook";
  try {
    my $connector = $package->new($webhook_id);
    $connector->load_config();
    $connector->save();
  }
  catch {
    ERROR("Connector '$webhook_name' failed to load: " . clean_error($_));
  };
}

sub delete_backlog_queue {
  my ($webhook_id) = @_;
  my $push  = Bugzilla->push_ext;
  my $webhook_name = 'Webhook_' . $webhook_id;
  my $connector = $push->connectors->by_name($webhook_name);
  my $queue = $connector->backlog;
  $queue->delete();
}

__PACKAGE__->NAME;
