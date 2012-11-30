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
use Bugzilla::Constants;
use Bugzilla::Search::Saved;

use Bugzilla::Extension::MyDashboard::Queries qw(QUERY_DEFS);

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
}

###########
# Objects #
###########

BEGIN {
    *Bugzilla::Search::Saved::in_mydashboard = \&_in_mydashboard;
}

sub _in_mydashboard {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    return $self->{'in_mydashboard'} if exists $self->{'in_mydashboard'};
    $self->{'in_mydashboard'} = $dbh->selectrow_array("
        SELECT 1 FROM mydashboard WHERE namedquery_id = ? AND user_id = ?",
        undef, $self->id, $self->user->id);
    return $self->{'in_mydashboard'};
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
        foreach my $q (@{$user->queries}, @{$user->queries_available}) {
            if (defined $params->{'in_mydashboard_' . $q->id}) {
                $sth_insert_fp->execute($q->id, $q->user->id) if !$q->in_mydashboard;
            }
            else {
                $sth_delete_fp->execute($q->id, $q->user->id) if $q->in_mydashboard;
            }
        }
    }
}

sub webservice {
    my ($self, $args) = @_;
    my $dispatch = $args->{dispatch};
    $dispatch->{MyDashboard} = "Bugzilla::Extension::MyDashboard::WebService";
}

__PACKAGE__->NAME;
