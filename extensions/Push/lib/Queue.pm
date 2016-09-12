# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Queue;

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
    return $dbh->selectrow_array("SELECT COUNT(*) FROM push");
}

sub oldest {
    my ($self) = @_;
    my @messages = $self->list(limit => 1);
    return scalar(@messages) ? $messages[0] : undef;
}

sub by_id {
    my ($self, $id) = @_;
    my @messages = $self->list(
        limit => 1,
        filter => "AND (push.id = $id)",
    );
    return scalar(@messages) ? $messages[0] : undef;
}

sub list {
    my ($self, %args) = @_;
    $args{limit} ||= 10;
    $args{filter} ||= '';
    my @result;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        SELECT id, push_ts, payload, change_set, routing_key
          FROM push
         WHERE (1 = 1) " .
               $args{filter} . "
         ORDER BY push_ts " .
         $dbh->sql_limit($args{limit})
    );
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref()) {
        push @result, Bugzilla::Extension::Push::Message->new({
            id          => $row->{id},
            push_ts     => $row->{push_ts},
            payload     => $row->{payload},
            change_set  => $row->{change_set},
            routing_key => $row->{routing_key},
        });
    }
    return @result;
}

1;
