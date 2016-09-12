# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Log;

use strict;
use warnings;

use Bugzilla;
use Bugzilla::Extension::Push::Message;

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);
    return $self;
}

sub count {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    return $dbh->selectrow_array("SELECT COUNT(*) FROM push_log");
}

sub list {
    my ($self, %args) = @_;
    $args{limit} ||= 10;
    $args{filter} ||= '';
    my @result;
    my $dbh = Bugzilla->dbh;

    my $ids = $dbh->selectcol_arrayref("
        SELECT id
          FROM push_log
         ORDER BY processed_ts DESC " .
         $dbh->sql_limit(100)
    );
    return Bugzilla::Extension::Push::LogEntry->new_from_list($ids);
}

1;
