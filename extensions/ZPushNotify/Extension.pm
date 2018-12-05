# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ZPushNotify;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Extension);
our $VERSION = '1';

use Bugzilla;

#
# insert into the notifications table
#

sub _notify {
  my ($bug_id, $delta_ts) = @_;

  # beacuse the push_notify table is hot, we defer updating it until the
  # request has completed.  this ensures we are outside the scope of any
  # transaction blocks.

  my $stash = Bugzilla->request_cache->{ZPushNotify_stash} ||= [];
  push @$stash, {bug_id => $bug_id, delta_ts => $delta_ts};
}

sub request_cleanup {
  my $stash = Bugzilla->request_cache->{ZPushNotify_stash} || return;

  my $dbh = Bugzilla->dbh;
  foreach my $rh (@$stash) {

    # using REPLACE INTO or INSERT .. ON DUPLICATE KEY UPDATE results in a
    # lock on the bugs table due to the FK.  this way is more verbose but
    # only locks the push_notify table.
    $dbh->bz_start_transaction();
    my ($id) = $dbh->selectrow_array("SELECT id FROM push_notify WHERE bug_id=?",
      undef, $rh->{bug_id});
    if ($id) {
      $dbh->do("UPDATE push_notify SET delta_ts=? WHERE id=?",
        undef, $rh->{delta_ts}, $id);
    }
    else {
      $dbh->do("INSERT INTO push_notify (bug_id, delta_ts) VALUES (?, ?)",
        undef, $rh->{bug_id}, $rh->{delta_ts});
    }
    $dbh->bz_commit_transaction();
  }
}

#
# object hooks
#

sub object_end_of_create {
  my ($self, $args) = @_;
  my $object = $args->{object};
  return unless Bugzilla->params->{enable_simple_push};
  return unless $object->isa('Bugzilla::Flag');
  _notify($object->bug->id, $object->creation_date);
}

sub flag_updated {
  my ($self, $args) = @_;
  my $flag      = $args->{flag};
  my $timestamp = $args->{timestamp};
  my $changes   = $args->{changes};
  return unless Bugzilla->params->{enable_simple_push};
  return unless scalar(keys %$changes);
  _notify($flag->bug->id, $timestamp);
}

sub flag_deleted {
  my ($self, $args) = @_;
  my $flag      = $args->{flag};
  my $timestamp = $args->{timestamp};
  return unless Bugzilla->params->{enable_simple_push};
  _notify($flag->bug->id, $timestamp);
}

sub attachment_end_of_update {
  my ($self, $args) = @_;
  return unless Bugzilla->params->{enable_simple_push};
  return unless scalar keys %{$args->{changes}};
  return unless my $object = $args->{object};
  _notify($object->bug->id, $object->modification_time);
}

sub object_before_delete {
  my ($self, $args) = @_;
  return unless Bugzilla->params->{enable_simple_push};
  return unless my $object = $args->{object};
  if ($object->isa('Bugzilla::Attachment')) {
    my $timestamp = Bugzilla->dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    _notify($object->bug->id, $timestamp);
  }
}

sub bug_end_of_update_delta_ts {
  my ($self, $args) = @_;
  return unless Bugzilla->params->{enable_simple_push};
  _notify($args->{bug_id}, $args->{timestamp});
}

sub bug_end_of_create {
  my ($self, $args) = @_;
  return unless Bugzilla->params->{enable_simple_push};
  _notify($args->{bug}->id, $args->{timestamp});
}

#
# schema / param
#

sub db_schema_abstract_schema {
  my ($self, $args) = @_;
  $args->{'schema'}->{'push_notify'} = {
    FIELDS => [
      id     => {TYPE => 'INTSERIAL', NOTNULL => 1, PRIMARYKEY => 1,},
      bug_id => {
        TYPE       => 'INT3',
        NOTNULL    => 1,
        REFERENCES => {TABLE => 'bugs', COLUMN => 'bug_id', DELETE => 'CASCADE'},
      },
      delta_ts => {TYPE => 'DATETIME', NOTNULL => 1,},
    ],
    INDEXES => [push_notify_idx => {FIELDS => ['bug_id'], TYPE => 'UNIQUE',},],
  };
}

sub config_modify_panels {
  my ($self, $args) = @_;
  push @{$args->{panels}->{advanced}->{params}},
    {name => 'enable_simple_push', type => 'b', default => 0,};
}

__PACKAGE__->NAME;
