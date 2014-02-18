# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::UserProfile::Util;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw( update_statistics_by_user
                  tag_for_recount_from_bug
                  last_user_activity );

use Bugzilla;

sub update_statistics_by_user {
    my ($user_id) = @_;

    # run all our queries on the slaves

    my $dbh = Bugzilla->switch_to_shadow_db();

    my $now = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

    # grab the current values

    my $last_statistics_ts = _get_last_statistics_ts($user_id);

    my $statistics = _get_stats($user_id, 'profiles_statistics',          'name');
    my $by_status  = _get_stats($user_id, 'profiles_statistics_status',   'status');
    my $by_product = _get_stats($user_id, 'profiles_statistics_products', 'product');

    # bugs filed
    _update_statistics($statistics, 'bugs_filed', [ $user_id ], <<EOF);
    SELECT COUNT(*)
      FROM bugs
     WHERE bugs.reporter = ?
EOF

    # comments made
    _update_statistics($statistics, 'comments', [ $user_id ], <<EOF);
    SELECT COUNT(*)
      FROM longdescs
     WHERE who = ?
EOF

    # commented on
    _update_statistics($statistics, 'commented_on', [ $user_id ], <<EOF);
    SELECT COUNT(*) FROM (
        SELECT longdescs.bug_id
          FROM longdescs
         WHERE who = ?
         GROUP BY longdescs.bug_id
    ) AS temp
EOF

    # confirmed
    _update_statistics($statistics, 'confirmed', [ $user_id, _field_id('bug_status') ], <<EOF);
    SELECT COUNT(*)
      FROM bugs_activity
     WHERE who = ?
           AND fieldid = ?
           AND removed = 'UNCONFIRMED'
           AND added = 'NEW'
EOF

    # patches submitted
    _update_statistics($statistics, 'patches', [ $user_id ], <<EOF);
    SELECT COUNT(*)
      FROM attachments
     WHERE submitter_id = ?
           AND (ispatch = 1
                OR mimetype = 'text/x-github-pull-request'
                OR mimetype = 'text/x-review-board-request')
EOF

    # patches reviewed
    _update_statistics($statistics, 'reviews', [ $user_id ], <<EOF);
    SELECT COUNT(*)
      FROM flags
           INNER JOIN attachments ON attachments.attach_id = flags.attach_id
     WHERE setter_id = ?
           AND (attachments.ispatch = 1
                OR attachments.mimetype = 'text/x-github-pull-request'
                OR attachments.mimetype = 'text/x-review-board-request')
           AND status IN ('+', '-')
EOF

    # assigned to
    _update_statistics($statistics, 'assigned', [ $user_id ], <<EOF);
    SELECT COUNT(*)
      FROM bugs
     WHERE assigned_to = ?
EOF

    # qa contact
    _update_statistics($statistics, 'qa_contact', [ $user_id ], <<EOF);
    SELECT COUNT(*)
      FROM bugs
     WHERE qa_contact = ?
EOF

    # bugs touched
    _update_statistics($statistics, 'touched', [ $user_id, $user_id], <<EOF);
    SELECT COUNT(*) FROM (
        SELECT bugs_activity.bug_id
          FROM bugs_activity
         WHERE who = ?
         GROUP BY bugs_activity.bug_id
        UNION
        SELECT longdescs.bug_id
          FROM longdescs
         WHERE who = ?
         GROUP BY longdescs.bug_id
    ) temp
EOF

    # activity by status/resolution, and product
    _activity_by_status($by_status, $user_id);
    _activity_by_product($by_product, $user_id);

    # if nothing is dirty, no need to do anything else
    if ($last_statistics_ts) {
        return unless _has_dirty($statistics)
            || _has_dirty($by_status)
            || _has_dirty($by_product);
    }

    # switch back to the main db for updating

    $dbh = Bugzilla->switch_to_main_db();
    $dbh->bz_start_transaction();

    # commit updated statistics

    _set_stats($statistics, $user_id, 'profiles_statistics',          'name')
        if _has_dirty($statistics);
    _set_stats($by_status,  $user_id, 'profiles_statistics_status',   'status')
        if _has_dirty($by_status);
    _set_stats($by_product, $user_id, 'profiles_statistics_products', 'product')
        if _has_dirty($by_product);

    # update the user's last_statistics_ts
    _set_last_statistics_ts($user_id, $now);

    $dbh->bz_commit_transaction();
}

sub tag_for_recount_from_bug {
    my ($bug_id) = @_;
    my $dbh = Bugzilla->dbh;
    # get a list of all users associated with this bug
    my $user_ids = $dbh->selectcol_arrayref(<<EOF, undef, $bug_id, _field_id('cc'), $bug_id);
    SELECT DISTINCT user_id
      FROM (
           SELECT DISTINCT who AS user_id
             FROM bugs_activity
            WHERE bug_id = ?
                  AND fieldid <> ?
            UNION ALL
           SELECT DISTINCT who AS user_id
             FROM longdescs
            WHERE bug_id = ?
    ) tmp
EOF
    # clear last_statistics_ts
    $dbh->do(
        "UPDATE profiles SET last_statistics_ts=NULL WHERE " . $dbh->sql_in('userid', $user_ids)
    );
    return scalar(@$user_ids);
}

sub last_user_activity {
    # last comment, or change to a bug (excluding CC changes)
    my ($user_id) = @_;
    return Bugzilla->dbh->selectrow_array(<<EOF, undef, $user_id, $user_id, _field_id('cc'));
    SELECT MAX(bug_when)
      FROM (
           SELECT MAX(bug_when) AS bug_when
             FROM longdescs
            WHERE who = ?
            UNION ALL
           SELECT MAX(bug_when) AS bug_when
             FROM bugs_activity
            WHERE who = ?
                  AND fieldid <> ?
           ) tmp
EOF
}

# for performance reasons hit the db directly rather than using the user object

sub _get_last_statistics_ts {
    my ($user_id) = @_;
    return Bugzilla->dbh->selectrow_array(
        "SELECT last_statistics_ts FROM profiles WHERE userid = ?",
        undef, $user_id
    );
}

sub _set_last_statistics_ts {
    my ($user_id, $timestamp) = @_;
    Bugzilla->dbh->do(
        "UPDATE profiles SET last_statistics_ts = ? WHERE userid = ?",
        undef,
        $timestamp, $user_id,
    );
}

sub _update_statistics {
    my ($statistics, $name, $values, $sql) = @_;
    my ($count) = Bugzilla->dbh->selectrow_array($sql, undef, @$values);
    if (!exists $statistics->{$name}) {
        $statistics->{$name} = {
            id    => 0,
            count => $count,
            dirty => 1,
        };
    } elsif ($statistics->{$name}->{count} != $count) {
        $statistics->{$name}->{count} = $count;
        $statistics->{$name}->{dirty} = 1;
    };
}

sub _activity_by_status {
    my ($by_status, $user_id) = @_;
    my $dbh = Bugzilla->dbh;

    # we actually track both status and resolution changes as statuses
    my @values = ($user_id, _field_id('bug_status'), $user_id, _field_id('resolution'));
    my $rows = $dbh->selectall_arrayref(<<EOF, { Slice => {} }, @values);
    SELECT added AS status, COUNT(*) AS count
      FROM bugs_activity
     WHERE who = ?
           AND fieldid = ?
     GROUP BY added
     UNION ALL
    SELECT CONCAT('RESOLVED/', added) AS status, COUNT(*) AS count
      FROM bugs_activity
     WHERE who = ?
           AND fieldid = ?
           AND added != ''
     GROUP BY added
EOF

    foreach my $row (@$rows) {
        my $status = $row->{status};
        if (!exists $by_status->{$status}) {
            $by_status->{$status} = {
                id    => 0,
                count => $row->{count},
                dirty => 1,
            };
        } elsif ($by_status->{$status}->{count} != $row->{count}) {
            $by_status->{$status}->{count} = $row->{count};
            $by_status->{$status}->{dirty} = 1;
        }
    }
}

sub _activity_by_product {
    my ($by_product, $user_id) = @_;
    my $dbh = Bugzilla->dbh;

    my %products;

    # changes
    my $rows = $dbh->selectall_arrayref(<<EOF, { Slice => {} }, $user_id);
    SELECT products.name AS product, count(*) AS count
      FROM bugs_activity
           INNER JOIN bugs ON bugs.bug_id = bugs_activity.bug_id
           INNER JOIN products ON products.id = bugs.product_id
     WHERE who = ?
     GROUP BY bugs.product_id
EOF
    map { $products{$_->{product}} += $_->{count} } @$rows;

    # comments
    $rows = $dbh->selectall_arrayref(<<EOF, { Slice => {} }, $user_id);
    SELECT products.name AS product, count(*) AS count
      FROM longdescs
           INNER JOIN bugs ON bugs.bug_id = longdescs.bug_id
           INNER JOIN products ON products.id = bugs.product_id
     WHERE who = ?
     GROUP BY bugs.product_id
EOF
    map { $products{$_->{product}} += $_->{count} } @$rows;

    # store only the top 10 and 'other' (which is an empty string)
    my @sorted = sort { $products{$b} <=> $products{$a} } keys %products;
    my @other;
    @other = splice(@sorted, 10) if scalar(@sorted) > 10;
    map { $products{''} += $products{$_} } @other;
    push @sorted, '' if $products{''};

    # update by_product
    foreach my $product (@sorted) {
        if (!exists $by_product->{$product}) {
            $by_product->{$product} = {
                id    => 0,
                count => $products{$product},
                dirty => 1,
            };
        } elsif ($by_product->{$product}->{count} != $products{$product}) {
            $by_product->{$product}->{count} = $products{$product};
            $by_product->{$product}->{dirty} = 1;
        }
    }
    foreach my $product (keys %$by_product) {
        if (!grep { $_ eq $product } @sorted) {
            delete $by_product->{$product};
        }
    }
}

our $_field_id_cache;
sub _field_id {
    my ($name) = @_;
    if (!$_field_id_cache) {
        my $rows = Bugzilla->dbh->selectall_arrayref("SELECT id, name FROM fielddefs");
        foreach my $row (@$rows) {
            $_field_id_cache->{$row->[1]} = $row->[0];
        }
    }
    return $_field_id_cache->{$name};
}

sub _get_stats {
    my ($user_id, $table, $name_field) = @_;
    my $result = {};
    my $rows = Bugzilla->dbh->selectall_arrayref(
        "SELECT * FROM $table WHERE user_id = ?",
        { Slice => {} },
        $user_id,
    );
    foreach my $row (@$rows) {
        unless (defined $row->{$name_field}) {
            print "$user_id $table $name_field\n";
            die;
        }
        $result->{$row->{$name_field}} = {
            id    => $row->{id},
            count => $row->{count},
            dirty => 0,
        }
    }
    return $result;
}

sub _set_stats {
    my ($statistics, $user_id, $table, $name_field) = @_;
    my $dbh = Bugzilla->dbh;
    foreach my $name (keys %$statistics) {
        next unless $statistics->{$name}->{dirty};
        if ($statistics->{$name}->{id}) {
            $dbh->do(
                "UPDATE $table SET count = ? WHERE user_id = ? AND $name_field = ?",
                undef,
                $statistics->{$name}->{count}, $user_id, $name,
            );
        } else {
            $dbh->do(
                "INSERT INTO $table(user_id, $name_field, count) VALUES (?, ?, ?)",
                undef,
                $user_id, $name, $statistics->{$name}->{count},
            );
        }
    }
}

sub _has_dirty {
    my ($statistics) = @_;
    foreach my $name (keys %$statistics) {
        return 1 if $statistics->{$name}->{dirty};
    }
    return 0;
}

1;
