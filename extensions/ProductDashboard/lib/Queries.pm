# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Extension::ProductDashboard::Queries;

use strict;

use base qw(Exporter);
@Bugzilla::Extension::ProductDashboard::Queries::EXPORT = qw(
    total_bugs
    total_open_bugs
    total_closed_bugs
    by_version
    by_value_summary
    by_milestone
    by_priority
    by_severity
    by_component
    by_assignee
    by_status
    by_duplicate
    by_popularity
    recently_opened
    recently_closed
    total_bug_milestone
    bug_milestone_by_status
);

use Bugzilla::CGI;
use Bugzilla::User;
use Bugzilla::Search;
use Bugzilla::Util;
use Bugzilla::Component;
use Bugzilla::Version;
use Bugzilla::Milestone;

use Bugzilla::Extension::ProductDashboard::Util qw(open_states closed_states);

sub total_bugs {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    return $dbh->selectrow_array("SELECT COUNT(bug_id)
                                    FROM bugs 
                                   WHERE product_id = ?", undef, $product->id);
}

sub total_open_bugs {
    my $product = shift;
    my $bug_status = shift;
    my $dbh = Bugzilla->dbh;

    return $dbh->selectrow_array("SELECT COUNT(bug_id) 
                                    FROM bugs 
                                   WHERE bug_status IN (" . open_states() . ") 
                                         AND product_id = ?", undef, $product->id);
}

sub total_closed_bugs {
    my $product = shift;
    my $dbh = Bugzilla->dbh;

    return $dbh->selectrow_array("SELECT COUNT(bug_id) 
                                    FROM bugs 
                                   WHERE bug_status IN ('CLOSED') 
                                         AND product_id = ?", undef, $product->id);
}

sub bug_link_all {
    my $product = shift;

    return correct_urlbase() . 'buglist.cgi?product=' . url_quote($product->name);
}

sub bug_link_open {
    my $product = shift;

    return correct_urlbase() . 'buglist.cgi?product=' . url_quote($product->name) . "&bug_status=__open__";
}

sub bug_link_closed {
    my $product = shift;

    return correct_urlbase() . 'buglist.cgi?product=' . url_quote($product->name) . "&bug_status=__closed__";
}

sub by_version {
    my ($product, $bug_status) = @_;
    my $dbh = Bugzilla->dbh;
    my $extra;

    $extra = "AND bugs.bug_status IN (" . open_states() . ")" if $bug_status eq 'open';
    $extra = "AND bugs.bug_status IN (" . closed_states() . ")" if $bug_status eq 'closed';

    return $dbh->selectall_arrayref("SELECT version, COUNT(bug_id) 
                                       FROM bugs 
                                      WHERE product_id = ? 
                                            $extra
                                      GROUP BY version
                                      ORDER BY COUNT(bug_id) DESC", undef, $product->id);
}

sub by_milestone {
    my ($product, $bug_status) = @_;
    my $dbh = Bugzilla->dbh;
    my $extra;

    $extra = "AND bugs.bug_status IN (" . open_states() . ")" if $bug_status eq 'open';
    $extra = "AND bugs.bug_status IN (" . closed_states() . ")" if $bug_status eq 'closed';

    return $dbh->selectall_arrayref("SELECT target_milestone, COUNT(bug_id) 
                                       FROM bugs 
                                      WHERE product_id = ?
                                            $extra
                                      GROUP BY target_milestone
                                      ORDER BY COUNT(bug_id) DESC", undef, $product->id);
}

sub by_priority {
    my ($product, $bug_status) = @_;
    my $dbh = Bugzilla->dbh;
    my $extra;

    $extra = "AND bugs.bug_status IN (" . open_states() . ")" if $bug_status eq 'open';
    $extra = "AND bugs.bug_status IN (" . closed_states() . ")" if $bug_status eq 'closed';

    return $dbh->selectall_arrayref("SELECT priority, COUNT(bug_id) 
                                       FROM bugs 
                                      WHERE product_id = ?
                                            $extra
                                      GROUP BY priority
                                      ORDER BY COUNT(bug_id) DESC", undef, $product->id);
}

sub by_severity {
    my ($product, $bug_status) = @_;
    my $dbh = Bugzilla->dbh;
    my $extra;

    $extra = "AND bugs.bug_status IN (" . open_states() . ")" if $bug_status eq 'open';
    $extra = "AND bugs.bug_status IN (" . closed_states() . ")" if $bug_status eq 'closed';

    return $dbh->selectall_arrayref("SELECT bug_severity, COUNT(bug_id) 
                                       FROM bugs 
                                      WHERE product_id = ? 
                                            $extra
                                      GROUP BY bug_severity
                                      ORDER BY COUNT(bug_id) DESC", undef, $product->id);
}

sub by_component {
    my ($product, $bug_status) = @_;
    my $dbh = Bugzilla->dbh;
    my $extra;

    $extra = "AND bugs.bug_status IN (" . open_states() . ")" if $bug_status eq 'open';
    $extra = "AND bugs.bug_status IN (" . closed_states() . ")" if $bug_status eq 'closed';

    return $dbh->selectall_arrayref("SELECT components.name, COUNT(bugs.bug_id) 
                                       FROM bugs INNER JOIN components ON bugs.component_id = components.id 
                                      WHERE bugs.product_id = ?
                                            $extra
                                      GROUP BY components.name
                                      ORDER BY COUNT(bugs.bug_id) DESC", undef, $product->id);
}

sub by_value_summary {
    my ($product, $type, $value, $bug_status) = @_;
    my $dbh = Bugzilla->dbh;
    my $extra;

    my $query = "SELECT bugs.bug_id AS id, 
                        bugs.bug_status AS status,
                        bugs.version AS version,
                        components.name AS component,
                        bugs.bug_severity AS severity,
                        bugs.short_desc AS summary
                   FROM bugs, components
                  WHERE bugs.product_id = ?
                        AND bugs.component_id = components.id ";

    if ($type eq 'component') {
        Bugzilla::Component->check({ product => $product, name => $value });
        $query .= "AND components.name = ? " if $type eq 'component';
    } 
    elsif ($type eq 'version') {
        Bugzilla::Version->check({ product => $product, name => $value });
        $query .= "AND bugs.version = ? " if $type eq 'version';
    }
    elsif ($type eq 'target_milestone') {
        Bugzilla::Milestone->check({ product => $product, name => $value });
        $query .= "AND bugs.target_milestone = ? " if $type eq 'target_milestone';
    }

    $query .= "AND bugs.bug_status IN (" . open_states() . ") " if $bug_status eq 'open';
    $query .= "AND bugs.bug_status IN (" . closed_states() . ") " if $bug_status eq 'closed';

    trick_taint($value);

    my $past_due_bugs = $dbh->selectall_arrayref($query .
                                                 "AND (bugs.deadline IS NOT NULL AND bugs.deadline != '')
                                                  AND bugs.deadline < now() ORDER BY bugs.deadline LIMIT 10",
                                                 {'Slice' => {}}, $product->id, $value);

    my $updated_recently_bugs = $dbh->selectall_arrayref($query .
                                                         "AND bugs.delta_ts != bugs.creation_ts " .
                                                         "ORDER BY bugs.delta_ts DESC LIMIT 10",
                                                         {'Slice' => {}}, $product->id, $value);

    my $timestamp =  $dbh->selectrow_array("SELECT " . $dbh->sql_date_format("LOCALTIMESTAMP(0)", "%Y-%m-%d"));

    return { 
        timestamp        => $timestamp,
        past_due         => _filter_bugs($past_due_bugs),
        updated_recently => _filter_bugs($updated_recently_bugs),
    };
}

sub by_assignee {
    my ($product, $bug_status, $limit) = @_;
    my $dbh = Bugzilla->dbh;
    my $extra;

    $limit = detaint_natural($limit) ? $dbh->sql_limit($limit) : "";

    $extra = "AND bugs.bug_status IN (" . open_states() . ")" if $bug_status eq 'open';
    $extra = "AND bugs.bug_status IN (" . closed_states() . ")" if $bug_status eq 'closed';

    my @result = map { [ Bugzilla::User->new($_->[0]), $_->[1] ] }
        @{$dbh->selectall_arrayref("SELECT bugs.assigned_to AS userid, COUNT(bugs.bug_id)
                                      FROM bugs, profiles
                                     WHERE bugs.product_id = ?
                                           AND bugs.assigned_to = profiles.userid
                                           $extra
                                     GROUP BY profiles.login_name
                                     ORDER BY COUNT(bugs.bug_id) DESC $limit", 
                                   undef, $product->id)};

    return \@result;
}

sub by_status {
    my ($product, $bug_status) = @_;
    my $dbh = Bugzilla->dbh;
    my $extra;

    $extra = "AND bugs.bug_status IN (" . open_states() . ")" if $bug_status eq 'open';
    $extra = "AND bugs.bug_status IN (" . closed_states() . ")" if $bug_status eq 'closed';

    return $dbh->selectall_arrayref("SELECT bugs.bug_status, COUNT(bugs.bug_id) 
                                       FROM bugs
                                      WHERE bugs.product_id = ?
                                            $extra 
                                      GROUP BY bugs.bug_status
                                      ORDER BY COUNT(bugs.bug_id) DESC", undef, $product->id);
}

sub total_bug_milestone {
    my ($product, $milestone) = @_;
    my $dbh = Bugzilla->dbh;

    return $dbh->selectrow_array("SELECT COUNT(bug_id) 
                                    FROM bugs 
                                   WHERE target_milestone = ? 
                                         AND product_id = ?",
                                 undef, 
                                 $milestone->name,
                                 $product->id);

}

sub bug_milestone_by_status {
    my ($product, $milestone, $bug_status) = @_;
    my $dbh = Bugzilla->dbh;
    my $extra;

    $extra = "AND bugs.bug_status IN (" . open_states() . ")" if $bug_status eq 'open';
    $extra = "AND bugs.bug_status IN (" . closed_states() . ")" if $bug_status eq 'closed';

    return $dbh->selectrow_array("SELECT COUNT(bug_id)
                                    FROM bugs 
                                   WHERE target_milestone = ?
                                         AND product_id = ? $extra",
                                 undef,
                                 $milestone->name,
                                 $product->id);

}

sub by_duplicate {
    my ($product, $bug_status, $limit) = @_;
    my $dbh = Bugzilla->dbh;
    $limit = detaint_natural($limit) ? $dbh->sql_limit($limit) : "";

    my $extra;
    $extra = "AND bugs.bug_status IN (" . open_states() . ")" if $bug_status eq 'open';
    $extra = "AND bugs.bug_status IN (" . closed_states() . ")" if $bug_status eq 'closed';

    my $unfiltered_bugs = $dbh->selectall_arrayref("SELECT bugs.bug_id AS id,
                                                           bugs.bug_status AS status,
                                                           bugs.version AS version,
                                                           components.name AS component,
                                                           bugs.bug_severity AS severity,
                                                           bugs.short_desc AS summary,
                                                           COUNT(duplicates.dupe) AS dupe_count
                                                      FROM bugs, duplicates, components
                                                     WHERE bugs.product_id = ?
                                                           AND bugs.component_id = components.id
                                                           AND bugs.bug_id = duplicates.dupe_of
                                                           $extra
                                                  GROUP BY bugs.bug_id, bugs.bug_status, components.name,
                                                           bugs.bug_severity, bugs.short_desc
                                                    HAVING COUNT(duplicates.dupe) > 1
                                                  ORDER BY COUNT(duplicates.dupe) DESC $limit",
                                                   {'Slice' => {}}, $product->id);

    return _filter_bugs($unfiltered_bugs);
}

sub by_popularity {
    my ($product, $bug_status, $limit) = @_;
    my $dbh = Bugzilla->dbh;
    $limit = detaint_natural($limit) ? $dbh->sql_limit($limit) : ""; 

    my $extra;
    $extra = "AND bugs.bug_status IN (" . open_states() . ")" if $bug_status eq 'open';
    $extra = "AND bugs.bug_status IN (" . closed_states() . ")" if $bug_status eq 'closed';

    my $unfiltered_bugs = $dbh->selectall_arrayref("SELECT bugs.bug_id AS id,
                                                           bugs.bug_status AS status,
                                                           bugs.version AS version,
                                                           components.name AS component,
                                                           bugs.bug_severity AS severity,
                                                           bugs.short_desc AS summary,
                                                           bugs.votes AS votes
                                                      FROM bugs, components
                                                     WHERE bugs.product_id = ?
                                                           AND bugs.component_id = components.id
                                                           AND bugs.votes > 1
                                                           $extra
                                                  ORDER BY bugs.votes DESC $limit",
                                                   {'Slice' => {}}, $product->id);

    return _filter_bugs($unfiltered_bugs);
}

sub recently_opened {
    my ($params) = @_;
    my $dbh = Bugzilla->dbh;

    my $product   = $params->{'product'};
    my $days      = $params->{'days'};
    my $limit     = $params->{'limit'};
    my $date_from = $params->{'date_from'};
    my $date_to   = $params->{'date_to'};

    $days ||= 7;
    $limit = detaint_natural($limit) ? $dbh->sql_limit($limit) : "";

    my @values = ($product->id);

    my $date_part;
    if ($date_from && $date_to) {
        validate_date($date_from)
            || ThrowUserError('illegal_date', { date   => $date_from,
                                                format => 'YYYY-MM-DD' });
        validate_date($date_to)
            || ThrowUserError('illegal_date', { date   => $date_to,
                                                format => 'YYYY-MM-DD' });
        $date_part = "AND bugs.creation_ts >= ? AND bugs.creation_ts <= ?";
        push(@values, $date_from, $date_to);
    }
    else {
        $date_part = "AND bugs.creation_ts >= NOW() - " . $dbh->sql_to_days('?');
        push(@values, $days);
    }

    my $unfiltered_bugs = $dbh->selectall_arrayref("SELECT bugs.bug_id AS id,
                                                           bugs.bug_status AS status,
                                                           bugs.version AS version,
                                                           components.name AS component,
                                                           bugs.bug_severity AS severity,
                                                           bugs.short_desc AS summary
                                                      FROM bugs, components
                                                     WHERE bugs.product_id = ?
                                                           AND bugs.component_id = components.id
                                                           AND bugs.bug_status IN (" . open_states() . ")
                                                           $date_part
                                                  ORDER BY bugs.bug_id DESC $limit",
                                                   {'Slice' => {}}, @values);

    return _filter_bugs($unfiltered_bugs);
}

sub recently_closed {
    my ($params) = @_;
    my $dbh = Bugzilla->dbh;

    my $product   = $params->{'product'};
    my $days      = $params->{'days'};
    my $limit     = $params->{'limit'};
    my $date_from = $params->{'date_from'};
    my $date_to   = $params->{'date_to'};

    $days ||= 7;
    $limit = detaint_natural($limit) ? $dbh->sql_limit($limit) : "";

    my @values = ($product->id);

    my $date_part;
    if ($date_from && $date_to) {
        validate_date($date_from)
            || ThrowUserError('illegal_date', { date   => $date_from,
                                                format => 'YYYY-MM-DD' });
        validate_date($date_to)
            || ThrowUserError('illegal_date', { date   => $date_to,
                                                format => 'YYYY-MM-DD' });
        $date_part = "AND bugs.creation_ts >= ? AND bugs.creation_ts <= ?";
        push(@values, $date_from, $date_to);
    }
    else {
        $date_part = "AND bugs.creation_ts >= NOW() - " . $dbh->sql_to_days('?');
        push(@values, $days);
    }

    my $unfiltered_bugs =  $dbh->selectall_arrayref("SELECT DISTINCT bugs.bug_id AS id, 
                                                            bugs.bug_status AS status,
                                                            bugs.version AS version,
                                                            components.name AS component,
                                                            bugs.bug_severity AS severity,
                                                            bugs.short_desc AS summary
                                                       FROM bugs, components, bugs_activity
                                                      WHERE bugs.product_id = ?
                                                            AND bugs.component_id = components.id
                                                            AND bugs.bug_status IN (" . closed_states() . ")
                                                            AND bugs.bug_id = bugs_activity.bug_id
                                                            AND bugs_activity.added IN (" . closed_states() . ")
                                                            $date_part
                                                   ORDER BY bugs.bug_id DESC $limit",
                                                    {'Slice' => {}}, @values);

    return _filter_bugs($unfiltered_bugs);
}

sub _filter_bugs {
    my ($unfiltered_bugs) = @_;
    my $dbh = Bugzilla->dbh;

    return [] if !$unfiltered_bugs;

    my @unfiltered_bug_ids = map { $_->{'id'} } @$unfiltered_bugs;
    my %filtered_bug_ids = map { $_ => 1 } @{ Bugzilla->user->visible_bugs(\@unfiltered_bug_ids) };

    my @filtered_bugs;
    foreach my $bug (@$unfiltered_bugs) {
        next if !$filtered_bug_ids{$bug->{'id'}};
        push(@filtered_bugs, $bug);
    }

    return \@filtered_bugs;
}

1;
