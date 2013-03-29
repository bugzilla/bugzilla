# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MyDashboard::Queries;

use strict;

use Bugzilla;
use Bugzilla::Bug;
use Bugzilla::CGI;
use Bugzilla::Search;
use Bugzilla::Util qw(format_time datetime_from);

use Bugzilla::Extension::MyDashboard::Util qw(open_states quoted_open_states);
use Bugzilla::Extension::MyDashboard::TimeAgo qw(time_ago);

use DateTime;

use base qw(Exporter);
our @EXPORT = qw(
    QUERY_ORDER
    SELECT_COLUMNS
    QUERY_DEFS
    query_bugs
    query_flags
);

# Default sort order
use constant QUERY_ORDER => ("changeddate desc", "bug_id");

# List of columns that we will be selecting. In the future this should be configurable
# Share with buglist.cgi?
use constant SELECT_COLUMNS => qw(
    bug_id
    bug_status
    short_desc
    changeddate
);

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
                'bug_status'     => ['UNCONFIRMED', 'NEW'],
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
                'bug_status'     => [ map { $_->name } grep($_->name ne 'UNCONFIRMED' && $_->name ne 'NEW', open_states()) ],
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

    if ($user->showmybugslink) {
        my $query = Bugzilla->params->{mybugstemplate};
        my $login = $user->login;
        $query =~ s/%userid%/$login/;
        $query =~ s/^buglist.cgi\?//;
        push(@query_defs, {
            name        => 'mybugs',
            heading     => "My Bugs",
            saved       => 1,
            params      => $query,
        });
    }

    foreach my $q (@{$user->queries}) {
        next if !$q->in_mydashboard;
        push(@query_defs, { name    => $q->name,
                            saved   => 1,
                            params  => $q->url });
    }

    return @query_defs;
}

sub query_bugs {
    my $qdef     = shift;
    my $dbh      = Bugzilla->dbh;
    my $user     = Bugzilla->user;
    my $date_now = DateTime->now(time_zone => $user->timezone);

    ## HACK to remove POST
    delete $ENV{REQUEST_METHOD};

    my $params = new Bugzilla::CGI($qdef->{params});

    my $search = new Bugzilla::Search( fields => [ SELECT_COLUMNS ],
                                       params => scalar $params->Vars,
                                       order  => [ QUERY_ORDER ]);
    my $data = $search->data;

    my @bugs;
    foreach my $row (@$data) {
        my $bug = {};
        foreach my $column (SELECT_COLUMNS) {
            $bug->{$column} = shift @$row;
            if ($column eq 'changeddate') {
                $bug->{$column} = format_time($bug->{$column});
                my $date_then = datetime_from($bug->{$column});
                $bug->{'changeddate_fancy'} = time_ago($date_then, $date_now);
            }
        }
        push(@bugs, $bug);
    }

    return (\@bugs, $params->canonicalise_query());
}

sub query_flags {
    my ($type, $include_resolved) = @_;
    my $user     = Bugzilla->user;
    my $dbh      = Bugzilla->dbh;
    my $date_now = DateTime->now(time_zone => $user->timezone);

    ($type ne 'requestee' || $type ne 'requester')
        || ThrowCodeError('param_required', { param => 'type' });

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
             bugs.bug_status AS bug_status,
             bugs.short_desc AS bug_summary,
             flags.attach_id AS attach_id,
             attachments.ispatch AS is_patch,
             requesters.login_name AS requester,
             requestees.login_name AS requestee,
             " . $dbh->sql_date_format('flags.modification_date', '%Y-%m-%d %H:%i') . " AS updated
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
    $query .= " WHERE flags.status = '?' ";

    # Limit to open bugs only unless want to include resolved
    if (!$include_resolved) {
        $query .= " AND bugs.bug_status IN (" . join(',', quoted_open_states()) . ") ";
    }

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
    my $group_order_by = " GROUP BY flags.bug_id ORDER BY flags.modification_date, flagtypes.name";

    my $flags = [];
    if ($type eq 'requestee') {
        $flags = $dbh->selectall_arrayref($query .
                                          " AND requestees.login_name = ? " .
                                          $group_order_by,
                                          { Slice => {} }, $user->login);
    }

    if ($type eq 'requester') {
        $flags = $dbh->selectall_arrayref($query .
                                          " AND requesters.login_name = ? " .
                                          $group_order_by,
                                          { Slice => {} }, $user->login);
    }

    # Format the updated date specific to the user's timezone and add the fancy version
    foreach my $flag (@$flags) {
        $flag->{'updated'} = format_time($flag->{'updated'});
        my $date_then = datetime_from($flag->{'updated'});
        $flag->{'updated_fancy'} = time_ago($date_then, $date_now);
    }

    return $flags;
}

1;
