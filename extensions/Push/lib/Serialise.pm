# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Serialise;

use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Version;

use Scalar::Util 'blessed';
use JSON ();

my $_instance;
sub instance {
    $_instance ||= Bugzilla::Extension::Push::Serialise->_new();
    return $_instance;
}

sub _new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);
    return $self;
}

# given an object, serliase to a hash
sub object_to_hash {
    my ($self, $object, $is_shallow) = @_;

    my $method = lc(blessed($object));
    $method =~ s/::/_/g;
    $method =~ s/^bugzilla//;
    return unless $self->can($method);
    (my $name = $method) =~ s/^_//;

    # check for a cached hash
    my $cache = Bugzilla->request_cache;
    my $cache_id = "push." . ($is_shallow ? 'shallow.' : 'deep.') . $object;
    if (exists($cache->{$cache_id})) {
        return wantarray ? ($cache->{$cache_id}, $name) : $cache->{$cache_id};
    }

    # call the right method to serialise to a hash
    my $rh = $self->$method($object, $is_shallow);

    # store in cache
    if ($cache_id) {
        $cache->{$cache_id} = $rh;
    }

    return wantarray ? ($rh, $name) : $rh;
}

# given a changes hash, return an event hash
sub changes_to_event {
    my ($self, $changes) = @_;

    my $event = {};

    # create common (created and modified) fields
    $event->{'user'} = $self->object_to_hash(Bugzilla->user);
    my $timestamp =
        $changes->{'timestamp'}
        || Bugzilla->dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    $event->{'time'} = datetime_to_timestamp($timestamp);

    foreach my $change (@{$changes->{'changes'}}) {
        if (exists $change->{'field'}) {
            # map undef to emtpy
            hash_undef_to_empty($change);

            # custom_fields change from undef to empty, ignore these changes
            return if ($change->{'added'} || "") eq "" &&
                    ($change->{'removed'} || "") eq "";

            # use saner field serialisation
            my $field = $change->{'field'};
            $change->{'field'} = $field;

            if ($field eq 'priority' || $field eq 'target_milestone') {
                $change->{'added'} = _select($change->{'added'});
                $change->{'removed'} = _select($change->{'removed'});

            } elsif ($field =~ /^cf_/) {
                $change->{'added'} = _custom_field($field, $change->{'added'});
                $change->{'removed'} = _custom_field($field, $change->{'removed'});
            }

            $event->{'changes'} = [] unless exists $event->{'changes'};
            push @{$event->{'changes'}}, $change;
        }
    }

    return $event;
}

# bugzilla returns '---' or '--' for single-select fields that have no value
# selected.  it makes more sense to return an empty string.
sub _select {
    my ($value) = @_;
    return '' if $value eq '---' or $value eq '--';
    return $value;
}

# return an object which serialises to a json boolean, but still acts as a perl
# boolean
sub _boolean {
    my ($value) = @_;
    return $value ? JSON::true : JSON::false;
}

sub _string {
    my ($value) = @_;
    return defined($value) ? $value : '';
}

sub _time {
    my ($value) = @_;
    return defined($value) ? datetime_to_timestamp($value) : undef;
}

sub _integer {
    my ($value) = @_;
    return $value + 0;
}

sub _custom_field {
    my ($field, $value) = @_;
    $field = Bugzilla::Field->new({ name => $field }) unless blessed $field;

    if ($field->type == FIELD_TYPE_DATETIME) {
        return _time($value);

    } elsif ($field->type == FIELD_TYPE_SINGLE_SELECT) {
        return _select($value);

    } elsif ($field->type == FIELD_TYPE_MULTI_SELECT) {
        # XXX
        die "not implemented";

    } else {
        return _string($value);
    }
}

#
# class mappings
# automatically derrived from the class name
# Bugzilla::Bug --> _bug, Bugzilla::User --> _user, etc
#

sub _bug {
    my ($self, $bug) = @_;

    my $version = $bug->can('version_obj')
        ? $bug->version_obj
        : Bugzilla::Version->new({ name => $bug->version, product => $bug->product_obj });

    my $milestone;
    if (_select($bug->target_milestone) ne '') {
        $milestone = $bug->can('target_milestone_obj')
            ? $bug->target_milestone_obj
            : Bugzilla::Milestone->new({ name => $bug->target_milestone, product => $bug->product_obj });
    }

    my $status = $bug->can('status_obj')
        ? $bug->status_obj
        : Bugzilla::Status->new({ name => $bug->bug_status });

    my $rh = {
        id               => _integer($bug->bug_id),
        alias            => _string($bug->alias),
        assigned_to      => $self->_user($bug->assigned_to),
        classification   => _string($bug->classification),
        component        => $self->_component($bug->component_obj),
        creation_time    => _time($bug->creation_ts || $bug->delta_ts),
        flags            => (mapr { $self->_flag($_) } $bug->flags),
        is_private       => _boolean(!is_public($bug)),
        keywords         => (mapr { _string($_->name) } $bug->keyword_objects),
        last_change_time => _time($bug->delta_ts),
        operating_system => _string($bug->op_sys),
        platform         => _string($bug->rep_platform),
        priority         => _select($bug->priority),
        product          => $self->_product($bug->product_obj),
        qa_contact       => $self->_user($bug->qa_contact),
        reporter         => $self->_user($bug->reporter),
        resolution       => _string($bug->resolution),
        severity         => _string($bug->bug_severity),
        status           => $self->_status($status),
        summary          => _string($bug->short_desc),
        target_milestone => $self->_milestone($milestone),
        url              => _string($bug->bug_file_loc),
        version          => $self->_version($version),
        whiteboard       => _string($bug->status_whiteboard),
    };

    # add custom fields
    my @custom_fields = Bugzilla->active_custom_fields;
    foreach my $field (@custom_fields) {
        my $name = $field->name;

        # skip custom fields that are hidded from this product/component
        next if Bugzilla::Extension::BMO::cf_hidden_in_product(
            $name, $bug->product, $bug->component);

        $rh->{$name} = _custom_field($field, $bug->$name);
    }

    return $rh;
}

sub _user {
    my ($self, $user) = @_;
    return undef unless $user;
    return {
        id        => _integer($user->id),
        login     => _string($user->login),
        real_name => _string($user->name),
    };
}

sub _component {
    my ($self, $component) = @_;
    return {
        id   => _integer($component->id),
        name => _string($component->name),
    };
}

sub _attachment {
    my ($self, $attachment, $is_shallow) = @_;
    my $rh = {
        id               => _integer($attachment->id),
        content_type     => _string($attachment->contenttype),
        creation_time    => _time($attachment->attached),
        description      => _string($attachment->description),
        file_name        => _string($attachment->filename),
        flags            => (mapr { $self->_flag($_) } $attachment->flags),
        is_obsolete      => _boolean($attachment->isobsolete),
        is_patch         => _boolean($attachment->ispatch),
        is_private       => _boolean(!is_public($attachment)),
        last_change_time => _time($attachment->modification_time),
    };
    if (!$is_shallow) {
        $rh->{bug} = $self->_bug($attachment->bug);
    }
    return $rh;
}

sub _comment {
    my ($self, $comment, $is_shallow) = @_;
    my $rh = {
        id            => _integer($comment->bug_id),
        body          => _string($comment->body),
        creation_time => _time($comment->creation_ts),
        is_private    => _boolean($comment->is_private),
        number        => _integer($comment->count),
    };
    if (!$is_shallow) {
        $rh->{bug} = $self->_bug($comment->bug);
    }
    return $rh;
}

sub _product {
    my ($self, $product) = @_;
    return {
        id   => _integer($product->id),
        name => _string($product->name),
    };
}

sub _flag {
    my ($self, $flag) = @_;
    my $rh = {
        id    => _integer($flag->id),
        name  => _string($flag->type->name),
        value => _string($flag->status),
    };
    if ($flag->requestee) {
        $rh->{'requestee'} = $self->_user($flag->requestee);
    }
    return $rh;
}

sub _version {
    my ($self, $version) = @_;
    return {
        id   => _integer($version->id),
        name => _string($version->name),
    };
}

sub _milestone {
    my ($self, $milestone) = @_;
    return undef unless $milestone;
    return {
        id   => _integer($milestone->id),
        name => _string($milestone->name),
    };
}

sub _status {
    my ($self, $status) = @_;
    return {
        id   => _integer($status->id),
        name => _string($status->name),
    };
}

1;
