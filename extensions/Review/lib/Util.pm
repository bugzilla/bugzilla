# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Review::Util;
use strict;
use warnings;

use base qw(Exporter);
use Bugzilla;

our @EXPORT = qw( rebuild_review_counters );

sub rebuild_review_counters {
    my ($callback) = @_;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction;
    my $rows = $dbh->selectall_arrayref("
        SELECT flags.requestee_id AS user_id,
               flagtypes.name AS flagtype,
               COUNT(*) as count
          FROM flags
               INNER JOIN profiles ON profiles.userid = flags.requestee_id
               INNER JOIN flagtypes ON flagtypes.id = flags.type_id
         WHERE flags.status = '?'
               AND flagtypes.name IN ('review', 'feedback', 'needinfo')
         GROUP BY flags.requestee_id, flagtypes.name
    ", { Slice => {} });

    my ($count, $total, $current) = (1, scalar(@$rows), { id => 0 });
    foreach my $row (@$rows) {
        $callback->($count++, $total) if $callback;
        if ($row->{user_id} != $current->{id}) {
            _update_profile($dbh, $current) if $current->{id};
            $current = { id => $row->{user_id} };
        }
        $current->{$row->{flagtype}} = $row->{count};
    }
    _update_profile($dbh, $current) if $current->{id};
    $dbh->bz_commit_transaction;
}

sub _update_profile {
    my ($dbh, $data) = @_;
    $dbh->do("
        UPDATE profiles
           SET review_request_count = ?,
               feedback_request_count = ?,
               needinfo_request_count = ?
         WHERE userid = ?",
        undef,
        $data->{review} || 0,
        $data->{feedback} || 0,
        $data->{needinfo} || 0,
        $data->{id}
    );
}

1;
