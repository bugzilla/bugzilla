# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::BacklogQueue;

use strict;
use warnings;

use Bugzilla;
use Bugzilla::Extension::Push::BacklogMessage;

sub new {
    my ($class, $connector) = @_;
    my $self = {};
    bless($self, $class);
    $self->{connector} = $connector;
    return $self;
}

sub count {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    return $dbh->selectrow_array("
        SELECT COUNT(*)
          FROM push_backlog
         WHERE connector = ?",
        undef,
        $self->{connector});
}

sub oldest {
    my ($self) = @_;
    my @messages = $self->list(
        limit => 1,
        filter => 'AND ((next_attempt_ts IS NULL) OR (next_attempt_ts <= NOW()))',
    );
    return scalar(@messages) ? $messages[0] : undef;
}

sub by_id {
    my ($self, $id) = @_;
    my @messages = $self->list(
        limit => 1,
        filter => "AND (log.id = $id)",
    );
    return scalar(@messages) ? $messages[0] : undef;
}

sub list {
    my ($self, %args) = @_;
    $args{limit} ||= 10;
    $args{filter} ||= '';
    my @result;
    my $dbh = Bugzilla->dbh;

    my $filter_sql = $args{filter} || '';
    my $sth = $dbh->prepare("
        SELECT log.id, message_id, push_ts, payload, change_set, routing_key, attempt_ts, log.attempts
          FROM push_backlog log
               LEFT JOIN push_backoff off ON off.connector = log.connector
         WHERE log.connector = ? ".
               $args{filter} . "
         ORDER BY push_ts " .
         $dbh->sql_limit($args{limit})
    );
    $sth->execute($self->{connector});
    while (my $row = $sth->fetchrow_hashref()) {
        push @result, Bugzilla::Extension::Push::BacklogMessage->new({
            id          => $row->{id},
            message_id  => $row->{message_id},
            push_ts     => $row->{push_ts},
            payload     => $row->{payload},
            change_set  => $row->{change_set},
            routing_key => $row->{routing_key},
            connector   => $self->{connector},
            attempt_ts  => $row->{attempt_ts},
            attempts    => $row->{attempts},
        });
    }
    return @result;
}

#
# backoff
#

sub backoff {
    my ($self) = @_;
    if (!$self->{backoff}) {
        my $ra = Bugzilla::Extension::Push::Backoff->match({
            connector => $self->{connector}
        });
        if (@$ra) {
            $self->{backoff} = $ra->[0];
        } else {
            $self->{backoff} = Bugzilla::Extension::Push::Backoff->create({
                connector => $self->{connector}
            });
        }
    }
    return $self->{backoff};
}

sub reset_backoff {
    my ($self) = @_;
    my $backoff = $self->backoff;
    $backoff->reset();
    $backoff->update();
}

sub inc_backoff {
    my ($self) = @_;
    my $backoff = $self->backoff;
    $backoff->inc();
    $backoff->update();
}

sub connector {
    my ($self) = @_;
    return $self->{connector};
}

1;
