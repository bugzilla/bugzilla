# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugmailFilter::Filter;

use base qw(Bugzilla::Object);

use strict;
use warnings;

use Bugzilla::Component;
use Bugzilla::Error;
use Bugzilla::Extension::BugmailFilter::Constants;
use Bugzilla::Extension::BugmailFilter::FakeField;
use Bugzilla::Field;
use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::Util qw(trim);

use constant DB_TABLE => 'bugmail_filters';

use constant DB_COLUMNS => qw(
    id
    user_id
    product_id
    component_id
    field_name
    relationship
    action
);

use constant LIST_ORDER => 'id';

use constant UPDATE_COLUMNS => ();

use constant VALIDATORS => {
    user_id     => \&_check_user,
    field_name  => \&_check_field_name,
    action      => \&Bugzilla::Object::check_boolean,
};
use constant VALIDATOR_DEPENDENCIES => {
    component_id    => [ 'product_id' ],
};

use constant AUDIT_CREATES => 0;
use constant AUDIT_UPDATES => 0;
use constant AUDIT_REMOVES => 0;
use constant USE_MEMCACHED => 0;

# getters

sub user {
    my ($self) = @_;
    return Bugzilla::User->new({ id => $self->{user_id}, cache => 1 });
}

sub product {
    my ($self) = @_;
    return $self->{product_id}
        ? Bugzilla::Product->new({ id => $self->{product_id}, cache => 1 })
        : undef;
}

sub product_name {
    my ($self) = @_;
    return $self->{product_name} //= $self->{product_id} ? $self->product->name : '';
}

sub component {
    my ($self) = @_;
    return $self->{component_id}
        ? Bugzilla::Component->new({ id => $self->{component_id}, cache => 1 })
        : undef;
}

sub component_name {
    my ($self) = @_;
    return $self->{component_name} //= $self->{component_id} ? $self->component->name : '';
}

sub field_name {
    return $_[0]->{field_name} //= '';
}

sub field_description {
    my ($self, $value) = @_;
    $self->{field_description} = $value if defined($value);
    return $self->{field_description};
}

sub field {
    my ($self) = @_;
    return unless $self->{field_name};
    if (!$self->{field}) {
        if (substr($self->{field_name}, 0, 1) eq '~') {
            # this should never happen
            die "not implemented";
        }
        foreach my $field (
            @{ Bugzilla::Extension::BugmailFilter::FakeField->fake_fields() },
            @{ Bugzilla::Extension::BugmailFilter::FakeField->tracking_flag_fields() },
        ) {
            if ($field->{name} eq $self->{field_name}) {
                return $self->{field} = $field;
            }
        }
        $self->{field} = Bugzilla::Field->new({ name => $self->{field_name}, cache => 1 });
    }
    return $self->{field};
}

sub relationship {
    return $_[0]->{relationship};
}

sub relationship_name {
    my ($self) = @_;
    foreach my $rel (@{ FILTER_RELATIONSHIPS() }) {
        return $rel->{name}
            if $rel->{value} == $self->{relationship};
    }
    return '?';
}

sub is_exclude {
    return $_[0]->{action} == 1;
}

sub is_include {
    return $_[0]->{action} == 0;
}

# validators

sub _check_user {
    my ($class, $user) = @_;
    $user || ThrowCodeError('param_required', { param => 'user' });
}

sub _check_field_name {
    my ($class, $field_name) = @_;
    return undef unless $field_name;
    if (substr($field_name, 0, 1) eq '~') {
        $field_name = lc(trim($field_name));
        $field_name =~ /^~[a-z0-9_\.]+$/
            || ThrowUserError('bugmail_filter_invalid');
        length($field_name) <= 64
            || ThrowUserError('bugmail_filter_too_long');
        return $field_name;
    }
    foreach my $rh (@{ FAKE_FIELD_NAMES() }) {
        return $field_name if $rh->{name} eq $field_name;
    }
    return $field_name
        if $field_name =~ /^tracking\./;
    Bugzilla::Field->check({ name => $field_name, cache => 1});
    return $field_name;
}

# methods

sub matches {
    my ($self, $args) = @_;

    if (my $field_name = $self->{field_name}) {
        if (substr($field_name, 0, 1) eq '~') {
            my $substring = quotemeta(substr($field_name, 1));
            if ($args->{field}->{field_name} !~ /$substring/i) {
                return 0;
            }
        }
        elsif ($field_name ne $args->{field}->{filter_field}) {
            return 0;
        }
    }

    if ($self->{product_id} && $self->{product_id} != $args->{product_id}) {
        return 0;
    }

    if ($self->{component_id} && $self->{component_id} != $args->{component_id}) {
        return 0;
    }

    if ($self->{relationship} && !$args->{rel_map}->[$self->{relationship}]) {
        return 0;
    }

    return 1;
}

1;
