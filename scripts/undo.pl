#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile catdir rel2abs);
use Cwd qw(realpath);
BEGIN {
    require lib;
    my $dir = rel2abs(catdir(dirname(__FILE__), '..'));
    lib->import($dir, catdir($dir, 'lib'), catdir($dir, qw(local lib perl5)));
}

use Bugzilla;
BEGIN { Bugzilla->extensions };
use Bugzilla::Extension::UserProfile::Util qw(tag_for_recount_from_bug);

use Try::Tiny;

# not involved with kmag
my $query = q{
    resolution = 'INACTIVE'
    AND NOT (
        triage_owner.login_name = 'mak77@bonardo.net'
        AND bugs.priority IN ('P4', 'P5', '--')
    )
    AND NOT (
        product.name = 'Toolkit' AND component.name = 'Add-ons Manager'
    )
    AND NOT (
        product.name = 'Toolkit' AND component.name LIKE 'WebExtensions%'
    )
    AND NOT (
        product.name = 'Core' AND component.name = 'XPConnect'
    )
};
undo($query);

sub undo {
    my @args = @_;
    my $changes = get_changes(@args);
    my $comments = get_comments(@args);

    my %action;
    while ($_ = $changes->()) {
        push @{ $action{$_->{bug_id}}{$_->{bug_when}}{remove_activities} }, { id => $_->{change_id} };
        $action{ $_->{bug_id} }{ $_->{bug_when} }{change}{ $_->{field_name} } = {
            replace => $_->{added},
            with    => $_->{removed},
        };
    }

    while ($_ = $comments->()) {
        push @{ $action{ $_->{bug_id} }{$_->{bug_when}}{remove_comments} }, {
            id => $_->{comment_id},
        };
    }

    my $dbh = Bugzilla->dbh;
    my @bug_ids = reverse sort { $a <=> $b } keys %action;
    say 'Found ', 0 + @bug_ids, ' bugs';
    foreach my $bug_id (@bug_ids) {
        $dbh->bz_start_transaction;
        say "Fix $bug_id";
        try {
            my ($delta_ts) = $dbh->selectrow_array(
                'SELECT delta_ts FROM bugs WHERE bug_id = ?',
                undef,
                $bug_id);
            my ($previous_last_ts) = $dbh->selectrow_array(
                q{
                    SELECT MAX(bug_when) FROM (
                        SELECT bug_when FROM bugs_activity WHERE bug_id = ? AND bug_when < ?
                        UNION
                        SELECT bug_when FROM longdescs WHERE bug_id = ? AND bug_when < ?
                        UNION
                        SELECT creation_ts AS bug_when FROM bugs WHERE bug_id = ?
                    ) as changes ORDER BY bug_when DESC
                },
                undef,
                $bug_id, $delta_ts,
                $bug_id, $delta_ts,
                $bug_id,
            );
            die 'cannot find previous last updated time' unless $previous_last_ts;
            my $action = delete $action{$bug_id}{$delta_ts};
            if (keys %{ $action{$bug_id}{$delta_ts}}) {
                die "skipping because more than one change\n";
            }
            elsif (!$action) {
                die "skipping because most recent change newer than automation change\n";
            }
            foreach my $field (keys %{ $action->{change} }) {
                my $change = $action->{change}{$field};
                if ($field eq 'cf_last_resolved' && !$change->{with}) {
                    $change->{with} = undef;
                }
                my $did = $dbh->do(
                    "UPDATE bugs SET $field = ? WHERE bug_id = ? AND $field = ?",
                    undef, $change->{with}, $bug_id, $change->{replace},
                );
                die "Failed to set $field to $change->{with}" unless $did;
            }
            $dbh->do('UPDATE bugs SET delta_ts = ?, lastdiffed = ? WHERE bug_id = ?', undef,
                $previous_last_ts, $previous_last_ts, $bug_id );
            my $del_comments = $dbh->prepare('DELETE FROM longdescs WHERE comment_id = ?');
            my $del_activity = $dbh->prepare('DELETE FROM bugs_activity WHERE id = ?');
            foreach my $comment (@{ $action->{remove_comments}}) {
                $del_comments->execute($comment->{id}) or die "failed to delete comment $comment->{id}";
            }
            foreach my $activity (@{ $action->{remove_activities}}) {
                $del_activity->execute($activity->{id}) or die "failed to delete comment $activity->{id}";
            }
            tag_for_recount_from_bug($bug_id);
            $dbh->bz_commit_transaction;
            sleep 1;
        } catch {
            chomp $_;
            say "Error updating $bug_id: $_";
            $dbh->bz_rollback_transaction;
        };
    }
    say 'Done.';
}

sub get_changes {
    my ($where, @bind) = @_;

    my $sql = qq{
        SELECT
            BA.id AS change_id,
            BA.bug_id,
            FD.name AS field_name,
            BA.removed,
            BA.added,
            BA.bug_when
        FROM
            bugs_activity AS BA
                JOIN
            fielddefs AS FD ON BA.fieldid = FD.id
                JOIN
            profiles AS changer ON changer.userid = BA.who
                JOIN
            (SELECT
                bug_id
            FROM
                bugs
            JOIN products AS product ON product.id = product_id
            JOIN components AS component ON component.id = component_id
            LEFT JOIN profiles AS triage_owner ON triage_owner.userid = component.triage_owner_id
            WHERE
                $where
            ) target_bugs ON BA.bug_id = target_bugs.bug_id
        WHERE
            changer.login_name = 'automation\@bmo.tld'
                AND BA.bug_when BETWEEN '2018-05-22' AND '2018-05-26'
    };
    my $sth = Bugzilla->dbh->prepare($sql);
    $sth->execute(@bind);

    return sub { $sth->fetchrow_hashref };
}

sub get_comments {
    my ($where, @bind) = @_;

    my $sql = qq{
        SELECT
            C.comment_id AS comment_id,
            C.bug_id AS bug_id,
            C.bug_when
        FROM
            longdescs AS C
                JOIN
            profiles AS commenter ON commenter.userid = C.who
                JOIN
            (SELECT
                bug_id
            FROM
                bugs
            JOIN products AS product ON product.id = product_id
            JOIN components AS component ON component.id = component_id
            LEFT JOIN profiles AS triage_owner ON triage_owner.userid = component.triage_owner_id
            WHERE
                $where
            ) target_bugs ON C.bug_id = target_bugs.bug_id
        WHERE
            commenter.login_name = 'automation\@bmo.tld'
                AND C.bug_when BETWEEN '2018-05-22' AND '2018-05-26'
    };
    my $sth = Bugzilla->dbh->prepare($sql);
    $sth->execute(@bind);

    return sub { $sth->fetchrow_hashref };
}
