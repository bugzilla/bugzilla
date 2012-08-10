# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MyDashboard::Util;

use strict;

use base qw(Exporter);
@Bugzilla::Extension::MyDashboard::Util::EXPORT = qw(
    open_states
    closed_states
    quoted_open_states
    quoted_closed_states
);

use Bugzilla::Status;

our $_open_states;
sub open_states {
    $_open_states ||= Bugzilla::Status->match({ is_open => 1, isactive => 1 });
    return wantarray ? @$_open_states : $_open_states;
}

our $_quoted_open_states;
sub quoted_open_states {
    my $dbh = Bugzilla->dbh;
    $_quoted_open_states ||= [ map { $dbh->quote($_->name) } open_states() ];
    return wantarray ? @$_quoted_open_states : $_quoted_open_states;
}

our $_closed_states;
sub closed_states {
    $_closed_states ||= Bugzilla::Status->match({ is_open => 0, isactive => 1 });
    return wantarray ? @$_closed_states : $_closed_states;
}

our $_quoted_closed_states;
sub quoted_closed_states {
    my $dbh = Bugzilla->dbh;
    $_quoted_closed_states ||= [ map { $dbh->quote($_->name) } closed_states() ];
    return wantarray ? @$_quoted_closed_states : $_quoted_closed_states;
}

1;
