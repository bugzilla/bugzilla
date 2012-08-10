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
use Bugzilla::Search;
use Bugzilla::Util;
use Bugzilla::Status;
use Bugzilla::Field;
use Bugzilla::Search::Saved;

use Bugzilla::Extension::MyDashboard::TimeAgo qw(time_ago);

use DateTime;

our $VERSION = BUGZILLA_VERSION;

sub QUERY_DEFS {
    my $user = Bugzilla->user;

    my @query_defs = (
        {
            name        => 'assignedbugs',
            heading     => 'Assigned to You',
            description => 'The bug has been assigned to you and it is not resolved or closed yet.',
            params      => {
                'bug_status'        => ['__open__'],
                'emailassigned_to1' => 1,
                'emailtype1'        => 'exact',
                'email1'            => $user->login
            }
        },
        {
            name        => 'newbugs',
            heading     => 'New Reported by You',
            description => 'You reported the bug but nobody has accepted it yet.',
            params      => {
                'bug_status'     => ['NEW'],
                'emailreporter1' => 1,
                'emailtype1'     => 'exact',
                'email1'         => $user->login
            }
        },
        {
            name        => 'inprogressbugs',
            heading     => "In Progress Reported by You",
            description => 'You reported the bug, the developer accepted the bug and is hopefully working on it.',
            params      => {
                'bug_status'     => [ map { $_->name } grep($_->name ne 'NEW' && $_->name ne 'MODIFIED', _open_states()) ],
                'emailreporter1' => 1,
                'emailtype1'     => 'exact',
                'email1'         => $user->login
            }
        },
        {
            name        => 'openccbugs',
            heading     => "You Are CC'd On",
            description => 'You are in the CC list of the bug, so you are watching it.',
            params      => {
                'bug_status' => ['__open__'],
                'emailcc1'   => 1,
                'emailtype1' => 'exact',
                'email1'     => $user->login
            }
        },
    );

    if (Bugzilla->params->{'useqacontact'}) {
        push(@query_defs, {
            name        => 'qacontactbugs',
            heading     => 'You Are QA Contact',
            description => 'You are the qa contact on this bug and it is not resolved or closed yet.',
            params      => {
                'bug_status'       => ['__open__'],
                'emailqa_contact1' => 1,
                'emailtype1'       => 'exact',
                'email1'           => $user->login
            }
        });
    }

    return @query_defs;
}

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

    # If we're using bug groups to restrict bug entry, we need to know who the
    # user is right from the start.
    my $user = Bugzilla->login(LOGIN_REQUIRED);

    # Switch to shadow db since we are just reading information
    Bugzilla->switch_to_shadow_db();

    _active_product_counts($vars);
    _standard_saved_queries($vars);
    _flags_requested($vars);

    $vars->{'severities'} = get_legal_field_values('bug_severity');
}

our $_open_states;
sub _open_states {
    $_open_states ||= Bugzilla::Status->match({ is_open => 1, isactive => 1 });
    return wantarray ? @$_open_states : $_open_states;
}

our $_quoted_open_states;
sub _quoted_open_states {
    my $dbh = Bugzilla->dbh;
    $_quoted_open_states ||= [ map { $dbh->quote($_->name) } _open_states() ];
    return wantarray ? @$_quoted_open_states : $_quoted_open_states;
}

sub _active_product_counts {
    my ($vars) = @_;
    my $dbh  = Bugzilla->dbh;
    my $user = Bugzilla->user;

    my @enterable_products = @{$user->get_enterable_products()};
    $vars->{'products'} 
        = $dbh->selectall_arrayref("SELECT products.name AS product, count(*) AS count
                                      FROM bugs,products
                                     WHERE bugs.product_id=products.id 
                                           AND products.isactive = 1 
                                           AND bugs.bug_status IN (" . join(',', _quoted_open_states()) . ")
                                           AND products.id IN (" . join(',', map { $_->id } @enterable_products) . ")
                                     GROUP BY products.name ORDER BY count DESC", { Slice => {} });

    $vars->{'products_buffer'} = "&" . join('&', map { "bug_status=" . $_->name } _open_states());
}

sub _standard_saved_queries {
    my ($vars) = @_;
    my $dbh  = Bugzilla->dbh;
    my $user = Bugzilla->user;

    # Default sort order
    my $order = ["bug_id"];

    # List of columns that we will be selecting. In the future this should be configurable
    # Share with buglist.cgi?
    my @select_columns = ('bug_id','product','bug_status','bug_severity','version', 'component','short_desc', 'changeddate');

    # Define the columns that can be selected in a query 
    my $columns = Bugzilla::Search::COLUMNS;

    # Weed out columns that don't actually exist and detaint along the way.
    @select_columns = grep($columns->{$_} && trick_taint($_), @select_columns);

    ### Standard query definitions
    my @query_defs = QUERY_DEFS;

    ### Saved query definitions 
    ### These are enabled through the userprefs.cgi UI
    foreach my $q (@{$user->queries}) {
        next if !$q->in_mydashboard;
        push(@query_defs, { name    => $q->name,
                            heading => $q->name,
                            saved   => 1,
                            params  => $q->url });
    }

    my $date_now = DateTime->now(time_zone => Bugzilla->local_timezone);

    ### Collect the query results for display in the template

    my @results;
    foreach my $qdef (@query_defs) {
        my $params = new Bugzilla::CGI($qdef->{params});

        my $search = new Bugzilla::Search( fields => \@select_columns,
                                           params => scalar $params->Vars,
                                           order  => $order );
        my $query = $search->sql();

        my $sth = $dbh->prepare($query);
        $sth->execute();

        my $rows = $sth->fetchall_arrayref();

        my @bugs;
        foreach my $row (@$rows) {
            my $bug = {};
            foreach my $column (@select_columns) {
                $bug->{$column} = shift @$row;
                if ($column eq 'changeddate') {
                   my $date_then = datetime_from($bug->{$column});
                   $bug->{'updated'} = time_ago($date_then, $date_now);
                }
            }
            push(@bugs, $bug);
        }

        $qdef->{bugs}   = \@bugs;
        $qdef->{buffer} = $params->canonicalise_query();

        push(@results, $qdef);
    }

    $vars->{'results'} = \@results;
}

sub _flags_requested {
    my ($vars) = @_;
    my $user = Bugzilla->user;
    my $dbh  = Bugzilla->dbh;

    my $attach_join_clause = "flags.attach_id = attachments.attach_id";
    if (Bugzilla->params->{insidergroup} && !$user->in_group(Bugzilla->params->{insidergroup})) {
        $attach_join_clause .= " AND attachments.isprivate < 1";
    }

    my $query = 
    # Select columns describing each flag, the bug/attachment on which
    # it has been set, who set it, and of whom they are requesting it.
    " SELECT flags.id AS id, 
             flagtypes.name AS type,
             flags.status AS status,
             flags.bug_id AS bug_id, 
             bugs.short_desc AS bug_summary,
             flags.attach_id AS attach_id, 
             attachments.description AS attach_summary,
             requesters.realname AS requester, 
             requestees.realname AS requestee,
             " . $dbh->sql_date_format('flags.creation_date', '%Y.%m.%d %H:%i') . " AS created
        FROM flags 
             LEFT JOIN attachments
                  ON ($attach_join_clause)
             INNER JOIN flagtypes
                  ON flags.type_id = flagtypes.id
             INNER JOIN bugs
                  ON flags.bug_id = bugs.bug_id
             LEFT JOIN profiles AS requesters
                  ON flags.setter_id = requesters.userid
             LEFT JOIN profiles AS requestees
                  ON flags.requestee_id  = requestees.userid
             LEFT JOIN bug_group_map AS bgmap
                  ON bgmap.bug_id = bugs.bug_id
             LEFT JOIN cc AS ccmap
                  ON ccmap.who = " . $user->id . "
                  AND ccmap.bug_id = bugs.bug_id ";

    # Limit query to pending requests and open bugs only
    $query .= " WHERE bugs.bug_status IN (" . join(',', _quoted_open_states()) . ")
                      AND flags.status = '?' ";

    # Weed out bug the user does not have access to
    $query .= " AND ((bgmap.group_id IS NULL)
                     OR bgmap.group_id IN (" . $user->groups_as_string . ")
                     OR (ccmap.who IS NOT NULL AND cclist_accessible = 1) 
                     OR (bugs.reporter = " . $user->id . " AND bugs.reporter_accessible = 1) 
                     OR (bugs.assigned_to = " . $user->id .") ";
    if (Bugzilla->params->{useqacontact}) {
        $query .= " OR (bugs.qa_contact = " . $user->id . ") ";
    }
    $query .= ") ";

    # Order the records (within each group).
    my $group_order_by = " GROUP BY flags.bug_id ORDER BY flagtypes.name, flags.creation_date";

    my $requestee_list = $dbh->selectall_arrayref($query . 
                                                  " AND requestees.login_name = ? " . 
                                                  $group_order_by, 
                                                  { Slice => {} }, $user->login);
    $vars->{'requestee_list'} = $requestee_list; 
    my $requester_list = $dbh->selectall_arrayref($query . 
                                                  " AND requesters.login_name = ? " . 
                                                  $group_order_by, 
                                                  { Slice => {} }, $user->login);
    $vars->{'requester_list'} = $requester_list;
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
