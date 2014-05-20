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
use Bugzilla::Flag;
use Bugzilla::Status qw(is_open_state);
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
            description => 'The bug has been assigned to you, and it is not resolved or closed.',
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
            description => 'You reported the bug; it\'s unconfirmed or new. No one has assigned themselves to fix it yet.',
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
            description => 'A developer accepted your bug and is working on it. (It has someone in the "Assigned to" field.)',
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
        {
            name        => 'lastvisitedbugs',
            heading     => 'Updated Since Last Visit',
            description => 'Bugs updated since list visited',
            params      => {
                o1 => 'lessthan',
                v1 => '%last_changed%',
                f1 => 'last_visit_ts',
            },
        },
    );

    if (Bugzilla->params->{'useqacontact'}) {
        push(@query_defs, {
            name        => 'qacontactbugs',
            heading     => 'You Are QA Contact',
            description => 'You are the qa contact on this bug, and it is not resolved or closed.',
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
    my $qdef         = shift;
    my $dbh          = Bugzilla->dbh;
    my $user         = Bugzilla->user;
    my $datetime_now = DateTime->now(time_zone => $user->timezone);

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
                my $datetime = datetime_from($bug->{$column});
                $datetime->set_time_zone($user->timezone);
                $bug->{$column} = $datetime->strftime('%Y-%m-%d %T %Z');
                $bug->{'changeddate_fancy'} = time_ago($datetime, $datetime_now);

                # Provide a version for use by Bug.history and also for looking up last comment.
                # We have to set to server's timezone and also subtract one second.
                $datetime->set_time_zone(Bugzilla->local_timezone);
                $datetime->subtract(seconds => 1);
                $bug->{changeddate_api} = $datetime->strftime('%Y-%m-%d %T');
            }
        }
        push(@bugs, $bug);
    }

    return (\@bugs, $params->canonicalise_query());
}

sub query_flags {
    my ($type) = @_;
    my $user         = Bugzilla->user;
    my $dbh          = Bugzilla->dbh;
    my $datetime_now = DateTime->now(time_zone => $user->timezone);

    ($type ne 'requestee' || $type ne 'requester')
        || ThrowCodeError('param_required', { param => 'type' });

    my $match_params = { status => '?' };

    if ($type eq 'requestee') {
        $match_params->{'requestee_id'} = $user->id;
    }
    else {
        $match_params->{'setter_id'} = $user->id;
    }

    my $matched = Bugzilla::Flag->match($match_params);

    return [] if !@$matched;

    my @unfiltered_flags;
    my %all_bugs; # Use hash to filter out duplicates
    foreach my $flag (@$matched) {
        next if ($flag->attach_id && $flag->attachment->isprivate && !$user->is_insider);

        my $data = {
            id          => $flag->id,
            type        => $flag->type->name,
            status      => $flag->status,
            attach_id   => $flag->attach_id,
            is_patch    => $flag->attach_id ? $flag->attachment->ispatch : 0,
            bug_id      => $flag->bug_id,
            requester   => $flag->setter->login,
            requestee   => $flag->requestee ? $flag->requestee->login : '',
            updated     => $flag->modification_date,
        };
        push(@unfiltered_flags, $data);

        # Record bug id for later retrieval of status/summary
        $all_bugs{$flag->{'bug_id'}}++;
    }

    # Filter the bug list based on permission to see the bug
    my %visible_bugs = map { $_ => 1 } @{ $user->visible_bugs([ keys %all_bugs ]) };

    return [] if !scalar keys %visible_bugs;

    # Get all bug statuses and summaries in one query instead of loading
    # many separate bug objects
    my $bug_rows = $dbh->selectall_arrayref("SELECT bug_id, bug_status, short_desc
                                               FROM bugs
                                              WHERE " . $dbh->sql_in('bug_id', [ keys %visible_bugs ]),
                                            { Slice => {} });
    foreach my $row (@$bug_rows) {
        $visible_bugs{$row->{'bug_id'}} = {
            bug_status => $row->{'bug_status'},
            short_desc => $row->{'short_desc'}
        };
    }

    # Now drop out any flags for bugs the user cannot see
    # or if the user did not want to see closed bugs
    my @filtered_flags;
    foreach my $flag (@unfiltered_flags) {
        # Skip this flag if the bug is not visible to the user
        next if !$visible_bugs{$flag->{'bug_id'}};

        # Include bug status and summary with each flag
        $flag->{'bug_status'}  = $visible_bugs{$flag->{'bug_id'}}->{'bug_status'};
        $flag->{'bug_summary'} = $visible_bugs{$flag->{'bug_id'}}->{'short_desc'};

        # Format the updated date specific to the user's timezone
        # and add the fancy human readable version
        my $datetime = datetime_from($flag->{'updated'});
        $datetime->set_time_zone($user->timezone);
        $flag->{'updated'} = $datetime->strftime('%Y-%m-%d %T %Z');
        $flag->{'updated_epoch'} = $datetime->epoch;
        $flag->{'updated_fancy'} = time_ago($datetime, $datetime_now);

        push(@filtered_flags, $flag);
    }

    return [] if !@filtered_flags;

    # Sort by most recently updated
    return [ sort { $b->{'updated_epoch'} <=> $a->{'updated_epoch'} } @filtered_flags ];
}

1;
