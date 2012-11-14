# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Backoff;

use strict;
use warnings;

use base 'Bugzilla::Object';

use Bugzilla;
use Bugzilla::Util;

#
# initialisation
#

use constant DB_TABLE => 'push_backoff';
use constant DB_COLUMNS => qw(
    id
    connector
    next_attempt_ts
    attempts
);
use constant UPDATE_COLUMNS => qw(
    next_attempt_ts
    attempts
);
use constant VALIDATORS => {
    connector        => \&_check_connector,
    next_attempt_ts  => \&_check_next_attempt_ts,
    attempts         => \&_check_attempts,
};
use constant LIST_ORDER => 'next_attempt_ts';

#
# accessors
#

sub connector       { return $_[0]->{'connector'};       }
sub next_attempt_ts { return $_[0]->{'next_attempt_ts'}; }
sub attempts        { return $_[0]->{'attempts'};        }

sub next_attempt_time {
    my ($self) = @_;
    if (!exists $self->{'next_attempt_time'}) {
        $self->{'next_attempt_time'} = datetime_from($self->next_attempt_ts)->epoch;
    }
    return $self->{'next_attempt_time'};
}

#
# mutators
#

sub reset {
    my ($self) = @_;
    $self->{next_attempt_ts} = Bugzilla->dbh->selectrow_array('SELECT NOW()');
    $self->{attempts} = 0;
    Bugzilla->push_ext->logger->debug(
        sprintf("resetting backoff for %s", $self->connector)
    );
}

sub inc {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    my $attempts = $self->attempts + 1;
    my $seconds = $attempts <= 4 ? 5 ** $attempts : 15 * 60;
    my ($date) = $dbh->selectrow_array("SELECT NOW() + " . $dbh->sql_interval($seconds, 'SECOND'));

    $self->{next_attempt_ts} = $date;
    $self->{attempts} = $attempts;
    Bugzilla->push_ext->logger->debug(
        sprintf("setting next attempt for %s to %s (attempt %s)", $self->connector, $date, $attempts)
    );
}

#
# validators
#

sub _check_connector {
    my ($invocant, $value) = @_;
    Bugzilla->push_ext->connectors->exists($value) || ThrowCodeError('push_invalid_connector');
    return $value;
}

sub _check_next_attempt_ts {
    my ($invocant, $value) = @_;
    return $value || Bugzilla->dbh->selectrow_array('SELECT NOW()');
}

sub _check_attempts {
    my ($invocant, $value) = @_;
    return $value || 0;
}

1;

