# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Metrics::Mysql;

use 5.10.1;
use strict;
use warnings;

use parent 'Bugzilla::DB::Mysql';

sub do {
    my ($self, @args) = @_;
    Bugzilla->metrics->db_start($args[0]);
    my $result = $self->SUPER::do(@args);
    Bugzilla->metrics->end();
    return $result;
}

sub selectall_arrayref {
    my ($self, @args) = @_;
    Bugzilla->metrics->db_start($args[0]);
    my $result = $self->SUPER::selectall_arrayref(@args);
    Bugzilla->metrics->end();
    return $result;
}

sub selectall_hashref {
    my ($self, @args) = @_;
    Bugzilla->metrics->db_start($args[0]);
    my $result = $self->SUPER::selectall_hashref(@args);
    Bugzilla->metrics->end();
    return $result;
}

sub selectcol_arrayref {
    my ($self, @args) = @_;
    Bugzilla->metrics->db_start($args[0]);
    my $result = $self->SUPER::selectcol_arrayref(@args);
    Bugzilla->metrics->end();
    return $result;
}

sub selectrow_array {
    my ($self, @args) = @_;
    Bugzilla->metrics->db_start($args[0]);
    my @result = $self->SUPER::selectrow_array(@args);
    Bugzilla->metrics->end();
    return wantarray ? @result : $result[0];
}

sub selectrow_arrayref {
    my ($self, @args) = @_;
    Bugzilla->metrics->db_start($args[0]);
    my $result = $self->SUPER::selectrow_arrayref(@args);
    Bugzilla->metrics->end();
    return $result;
}

sub selectrow_hashref {
    my ($self, @args) = @_;
    Bugzilla->metrics->db_start($args[0]);
    my $result = $self->SUPER::selectrow_hashref(@args);
    Bugzilla->metrics->end();
    return $result;
}

sub commit {
    my ($self, @args) = @_;
    Bugzilla->metrics->db_start('COMMIT');
    my $result = $self->SUPER::commit(@args);
    Bugzilla->metrics->end();
    return $result;
}

sub prepare {
    my ($self, @args) = @_;
    my $sth = $self->SUPER::prepare(@args);
    bless($sth, 'Bugzilla::Metrics::st');
    return $sth;
}

package Bugzilla::Metrics::st;

use 5.10.1;
use strict;
use warnings;

use base 'DBI::st';

sub execute {
    my ($self, @args) = @_;
    $self->{private_timer} = Bugzilla->metrics->db_start();
    my $result = $self->SUPER::execute(@args);
    Bugzilla->metrics->end();
    return $result;
}

sub fetchrow_array {
    my ($self, @args) = @_;
    my $timer = $self->{private_timer};
    Bugzilla->metrics->resume($timer);
    my @result = $self->SUPER::fetchrow_array(@args);
    Bugzilla->metrics->end($timer);
    return wantarray ? @result : $result[0];
}

sub fetchrow_arrayref {
    my ($self, @args) = @_;
    my $timer = $self->{private_timer};
    Bugzilla->metrics->resume($timer);
    my $result = $self->SUPER::fetchrow_arrayref(@args);
    Bugzilla->metrics->end($timer);
    return $result;
}

sub fetchrow_hashref {
    my ($self, @args) = @_;
    my $timer = $self->{private_timer};
    Bugzilla->metrics->resume($timer);
    my $result = $self->SUPER::fetchrow_hashref(@args);
    Bugzilla->metrics->end($timer);
    return $result;
}

sub fetchall_arrayref {
    my ($self, @args) = @_;
    my $timer = $self->{private_timer};
    Bugzilla->metrics->resume($timer);
    my $result = $self->SUPER::fetchall_arrayref(@args);
    Bugzilla->metrics->end($timer);
    return $result;
}

sub fetchall_hashref {
    my ($self, @args) = @_;
    my $timer = $self->{private_timer};
    Bugzilla->metrics->resume($timer);
    my $result = $self->SUPER::fetchall_hashref(@args);
    Bugzilla->metrics->end($timer);
    return $result;
}

1;
