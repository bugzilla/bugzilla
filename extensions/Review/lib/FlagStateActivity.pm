# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Review::FlagStateActivity;
use strict;
use warnings;

use Bugzilla::Error qw(ThrowUserError);
use Bugzilla::Util qw(trim datetime_from);
use List::MoreUtils qw(none);

use base qw( Bugzilla::Object );

use constant DB_TABLE      => 'flag_state_activity';
use constant LIST_ORDER    => 'id';
use constant AUDIT_CREATES => 0;
use constant AUDIT_UPDATES => 0;
use constant AUDIT_REMOVES => 0;

use constant DB_COLUMNS => qw(
    id
    flag_when
    type_id
    flag_id
    setter_id
    requestee_id
    bug_id
    attachment_id
    status
);


sub _check_param_required {
    my ($param) = @_;

    return sub {
        my ($invocant, $value) = @_;
        $value = trim($value)
            or ThrowCodeError('param_required', {param => $param});
        return $value;
    },
}

sub _check_date {
    my ($invocant, $date) = @_;

    $date = trim($date);
    datetime_from($date)
        or ThrowUserError('illegal_date', { date   => $date,
                                            format => 'YYYY-MM-DD HH24:MI:SS' });
    return $date;
}

sub _check_status {
    my ($self, $status) = @_;

    # - Make sure the status is valid.
    # - Make sure the user didn't request the flag unless it's requestable.
    #   If the flag existed and was requested before it became unrequestable,
    #   leave it as is.
    if (none { $status eq $_ } qw( X + - ? )) {
        ThrowUserError(
            'flag_status_invalid',
            {
                id     => $self->id,
                status => $status
            }
        );
    }
    return $status;
}

use constant VALIDATORS => {
    flag_when => \&_check_date,
    type_id   => _check_param_required('type_id'),
    flag_id   => _check_param_required('flag_id'),
    setter_id => _check_param_required('setter_id'),
    bug_id    => _check_param_required('bug_id'),
    status    => \&_check_status,
};

sub flag_when     { return $_[0]->{flag_when} }
sub type_id       { return $_[0]->{type_id} }
sub flag_id       { return $_[0]->{flag_id} }
sub setter_id     { return $_[0]->{setter_id} }
sub bug_id        { return $_[0]->{bug_id} }
sub requestee_id  { return $_[0]->{requestee_id} }
sub attachment_id { return $_[0]->{attachment_id} }
sub status        { return $_[0]->{status} }

sub type {
    my ($self) = @_;
    return $self->{type} //= Bugzilla::FlagType->new({ id => $self->type_id, cache => 1 });
}

sub setter {
    my ($self) = @_;
    return $self->{setter} //= Bugzilla::User->new({ id => $self->setter_id, cache => 1 });
}

sub requestee {
    my ($self) = @_;
    return undef unless defined $self->requestee_id;
    return $self->{requestee} //= Bugzilla::User->new({ id => $self->requestee_id, cache => 1 });
}

sub bug {
    my ($self) = @_;
    return $self->{bug} //= Bugzilla::Bug->new({ id => $self->bug_id, cache => 1 });
}

sub attachment {
    my ($self) = @_;
    return $self->{attachment} //=
        Bugzilla::Attachment->new({ id => $self->attachment_id, cache => 1 });
}

1;
