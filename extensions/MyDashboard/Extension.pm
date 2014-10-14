# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MyDashboard;

use strict;

use base qw(Bugzilla::Extension);

use Bugzilla;
use Bugzilla::Status 'is_open_state';

use Bugzilla::Constants;
use Bugzilla::Search::Saved;

use Bugzilla::Extension::MyDashboard::Queries qw(QUERY_DEFS);
use Bugzilla::Extension::MyDashboard::BugInterest;

our $VERSION = BUGZILLA_VERSION;

################
# Installation #
################

sub db_schema_abstract_schema {
    my ($self, $args) = @_;

    my $schema = $args->{schema};

    $schema->{'mydashboard'} = {
        FIELDS => [
            namedquery_id => {TYPE => 'INT3', NOTNULL => 1,
                              REFERENCES => {TABLE  => 'namedqueries',
                                             COLUMN => 'id',
                                             DELETE => 'CASCADE'}},
            user_id       => {TYPE => 'INT3', NOTNULL => 1,
                              REFERENCES => {TABLE  => 'profiles',
                                             COLUMN => 'userid',
                                             DELETE => 'CASCADE'}},
        ],
        INDEXES => [
            mydashboard_namedquery_id_idx => {FIELDS => [qw(namedquery_id user_id)],
                                              TYPE   => 'UNIQUE'},
            mydashboard_user_id_idx => ['user_id'],
        ],
    };

    $schema->{'bug_interest'} = {
        FIELDS => [
            id => { TYPE       => 'MEDIUMSERIAL',
                    NOTNULL    => 1,
                    PRIMARYKEY => 1 },

            bug_id => { TYPE       => 'INT3',
                        NOTNULL    => 1,
                        REFERENCES => { TABLE  => 'bugs',
                                        COLUMN => 'bug_id',
                                        DELETE => 'CASCADE' } },

            user_id => { TYPE       => 'INT3',
                         NOTNOLL    => 1,
                         REFERENCES => { TABLE  => 'profiles',
                                         COLUMN => 'userid' } },

            modification_time => { TYPE    => 'DATETIME',
                                   NOTNULL => 1 }
        ],
        INDEXES => [
            bug_interest_idx         => { FIELDS => [qw(bug_id user_id)],
                                          TYPE => 'UNIQUE' },
            bug_interest_user_id_idx => ['user_id']
        ],
    };
}

###########
# Objects #
###########

BEGIN {
    *Bugzilla::Search::Saved::in_mydashboard = \&_in_mydashboard;
    *Bugzilla::Component::watcher_ids        = \&_component_watcher_ids;
}

sub _in_mydashboard {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    return $self->{'in_mydashboard'} if exists $self->{'in_mydashboard'};
    $self->{'in_mydashboard'} = $dbh->selectrow_array("
        SELECT 1 FROM mydashboard WHERE namedquery_id = ? AND user_id = ?",
        undef, $self->id, Bugzilla->user->id);
    return $self->{'in_mydashboard'};
}

sub _component_watcher_ids {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    my $query = "SELECT user_id FROM component_watch
                  WHERE product_id = ?
                    AND (component_id = ?
                         OR component_id IS NULL
                         OR ? LIKE CONCAT(component_prefix, '%'))";

    $self->{watcher_ids} ||= $dbh->selectcol_arrayref($query, undef,
        $self->product_id, $self->id, $self->name);

    return $self->{watcher_ids};
}

#############
# Templates #
#############

sub page_before_template {
    my ($self, $args) = @_;
    my $page = $args->{'page_id'};
    my $vars = $args->{'vars'};

    return if $page ne 'mydashboard.html';

    # require user to be logged in for this page
    Bugzilla->login(LOGIN_REQUIRED);

    $vars->{queries} = [ QUERY_DEFS ];
}

#########
# Hooks #
#########

sub user_preferences {
    my ($self, $args) = @_;
    my $tab = $args->{'current_tab'};
    return unless $tab eq 'saved-searches';

    my $save    = $args->{'save_changes'};
    my $handled = $args->{'handled'};
    my $vars    = $args->{'vars'};

    my $dbh    = Bugzilla->dbh;
    my $user   = Bugzilla->user;
    my $params = Bugzilla->input_params;

    if ($save) {
        my $sth_insert_fp = $dbh->prepare('INSERT INTO mydashboard
                                           (namedquery_id, user_id)
                                           VALUES (?, ?)');
        my $sth_delete_fp = $dbh->prepare('DELETE FROM mydashboard
                                           WHERE namedquery_id = ?
                                           AND user_id = ?');
        foreach my $q (@{$user->queries}) {
            if (defined $params->{'in_mydashboard_' . $q->id}) {
                $sth_insert_fp->execute($q->id, $user->id) if !$q->in_mydashboard;
            }
            else {
                $sth_delete_fp->execute($q->id, $user->id) if $q->in_mydashboard;
            }
        }
    }
}

sub webservice {
    my ($self, $args) = @_;
    my $dispatch = $args->{dispatch};
    $dispatch->{MyDashboard} = "Bugzilla::Extension::MyDashboard::WebService";
}

sub bug_end_of_create {
    my ($self, $args) = @_;
    my ($bug, $params, $timestamp) = @$args{qw(bug params timestamp)};
    my $user = Bugzilla->user;

    # Anyone added to the CC list of a bug is now interested in that bug.
    foreach my $cc_user (@{ $bug->cc_users }) {
        next if $user->id == $cc_user->id;
        Bugzilla::Extension::MyDashboard::BugInterest->mark($cc_user->id, $bug->id, $timestamp);
    }

    # Anyone that is watching a component is interested when a bug is filed into the component.
    foreach my $watcher_id (@{ $bug->component_obj->watcher_ids }) {
        Bugzilla::Extension::MyDashboard::BugInterest->mark($watcher_id, $bug->id, $timestamp);
    }
}

sub bug_end_of_update {
    my ($self, $args) = @_;
    my ($bug, $old_bug, $changes, $timestamp) = @$args{qw(bug old_bug changes timestamp)};
    my $user = Bugzilla->user;

    # Anyone added to the CC list of a bug is now interested in that bug.
    my %old_cc = map { $_->id => $_ } grep { defined } @{ $old_bug->cc_users };
    my @added = grep { not $old_cc{ $_->id } } grep { defined } @{ $bug->cc_users };
    foreach my $cc_user (@added) {
        next if $user->id == $cc_user->id;
        Bugzilla::Extension::MyDashboard::BugInterest->mark($cc_user->id, $bug->id, $timestamp);
    }

    # Anyone that is watching a component is interested when a bug is filed into the component.
    if ($changes->{product} or $changes->{component}) {
        # All of the watchers would be interested in this bug update
        foreach my $watcher_id (@{ $bug->component_obj->watcher_ids }) {
            Bugzilla::Extension::MyDashboard::BugInterest->mark($watcher_id, $bug->id, $timestamp);
        }
    }

    if ($changes->{bug_status}) {
        my ($old_status, $new_status) = @{ $changes->{bug_status} };
        if (is_open_state($old_status) && !is_open_state($new_status)) {
            my @related_bugs = (@{ $bug->blocks_obj }, @{ $bug->depends_on_obj });
            my %involved;

            foreach my $related_bug (@related_bugs) {
                my @users = grep { defined } $related_bug->assigned_to,
                                             $related_bug->reporter,
                                             $related_bug->qa_contact,
                                             @{ $related_bug->cc_users };

                foreach my $involved_user (@users) {
                    $involved{ $involved_user->id }{ $related_bug->id } = 1;
                }
            }
            foreach my $involved_user_id (keys %involved) {
                foreach my $related_bug_id (keys %{$involved{$involved_user_id}}) {
                    Bugzilla::Extension::MyDashboard::BugInterest->mark($involved_user_id,
                                                                        $related_bug_id,
                                                                        $timestamp);
                }
            }
        }
    }
}

__PACKAGE__->NAME;
