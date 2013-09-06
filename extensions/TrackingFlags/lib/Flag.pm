# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TrackingFlags::Flag;

use base qw(Bugzilla::Object);

use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::Constants;
use Bugzilla::Util qw(detaint_natural trim);
use Bugzilla::Config qw(SetParam write_params);

use Bugzilla::Extension::TrackingFlags::Constants;
use Bugzilla::Extension::TrackingFlags::Flag::Bug;
use Bugzilla::Extension::TrackingFlags::Flag::Value;
use Bugzilla::Extension::TrackingFlags::Flag::Visibility;

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'tracking_flags';

use constant DB_COLUMNS => qw(
    id
    field_id
    name
    description
    type
    sortkey
    is_active
);

use constant LIST_ORDER => 'sortkey';

use constant UPDATE_COLUMNS => qw(
    name
    description
    type
    sortkey
    is_active
);

use constant VALIDATORS => {
    name        => \&_check_name,
    description => \&_check_description,
    type        => \&_check_type,
    sortkey     => \&_check_sortkey,
    is_active   => \&Bugzilla::Object::check_boolean,

};

use constant UPDATE_VALIDATORS => {
    name        => \&_check_name,
    description => \&_check_description,
    type        => \&_check_type,
    sortkey     => \&_check_sortkey,
    is_active   => \&Bugzilla::Object::check_boolean,
};

###############################
####      Methods          ####
###############################

sub new {
    my $class = shift;
    my $param = shift;
    my $cache = Bugzilla->request_cache;

    if (!ref $param
        && exists $cache->{'tracking_flags'}
        && exists $cache->{'tracking_flags'}->{$param})
    {
        return $cache->{'tracking_flags'}->{$param};
    }

    return $class->SUPER::new($param);
}

sub create {
    my $class = shift;
    my $params = shift;
    my $dbh = Bugzilla->dbh;
    my $flag;

    # Disable bug updates temporarily to avoid conflicts.
    SetParam('disable_bug_updates', 1);
    write_params();

    eval {
        $dbh->bz_start_transaction();

        $params = $class->run_create_validators($params);

        # We have to create an entry for this new flag
        # in the fielddefs table for use elsewhere. We cannot
        # use Bugzilla::Field->create as it will create the
        # additional tables needed by custom fields which we
        # do not need. Also we do this so as not to add a
        # another column to the bugs table.
        # We will create the entry as a custom field with a
        # type of FIELD_TYPE_EXTENSION so Bugzilla will skip
        # these field types in certain parts of the core code.
        $dbh->do("INSERT INTO fielddefs
                 (name, description, sortkey, type, custom, obsolete, buglist)
                 VALUES
                 (?, ?, ?, ?, ?, ?, ?)",
                 undef,
                 $params->{'name'},
                 $params->{'description'},
                 $params->{'sortkey'},
                 FIELD_TYPE_EXTENSION,
                 1, 0, 1);
        $params->{'field_id'} = $dbh->bz_last_key;

        $flag = $class->SUPER::create($params);

        $dbh->bz_commit_transaction();
    };
    my $error = "$@";
    SetParam('disable_bug_updates',  0);
    write_params();
    die $error if $error;

    return $flag;
}

sub update {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    my $old_self = $self->new($self->flag_id);

    # HACK! Bugzilla::Object::update uses hardcoded $self->id
    # instead of $self->{ID_FIELD} so we need to reverse field_id
    # and the real id temporarily
    my $field_id = $self->id;
    $self->{'field_id'} = $self->{'id'};

    my $changes = $self->SUPER::update(@_);

    $self->{'field_id'} = $field_id;

    # Update the fielddefs entry
    $dbh->do("UPDATE fielddefs SET name = ?, description = ? WHERE name = ?",
             undef,
             $self->name, $self->description, $old_self->name);

    # Update request_cache
    my $cache = Bugzilla->request_cache;
    if (exists $cache->{'tracking_flags'}) {
        $cache->{'tracking_flags'}->{$self->flag_id} = $self;
    }

    return $changes;
}

sub match {
    my $class = shift;
    my ($params) = @_;

    # Use later for preload
    my $bug_id = delete $params->{'bug_id'};

    # Retrieve all flags relevant for the given product and component
    if (!exists $params->{'id'}
        && ($params->{'component'} || $params->{'component_id'}
            || $params->{'product'} || $params->{'product_id'}))
    {
        my $visible_flags
            = Bugzilla::Extension::TrackingFlags::Flag::Visibility->match(@_);
        my @flag_ids = map { $_->tracking_flag_id } @$visible_flags;

        delete $params->{'component'} if exists $params->{'component'};
        delete $params->{'component_id'} if exists $params->{'component_id'};
        delete $params->{'product'} if exists $params->{'product'};
        delete $params->{'product_id'} if exists $params->{'product_id'};

        $params->{'id'} = \@flag_ids;
    }

    # We need to return inactive flags if a value has been set
    my $is_active_filter = delete $params->{is_active};

    my $flags = $class->SUPER::match($params);
    preload_all_the_things($flags, { bug_id => $bug_id });

    if ($is_active_filter) {
        $flags = [ grep { $_->is_active || exists $_->{bug_flag} } @$flags ];
    }
    return [ sort { $a->sortkey <=> $b->sortkey } @$flags ];
}

sub get_all {
    my $self = shift;
    my $cache = Bugzilla->request_cache;
    if (!exists $cache->{'tracking_flags'}) {
        my @tracking_flags = $self->SUPER::get_all(@_);
        preload_all_the_things(\@tracking_flags);
        my %tracking_flags_hash = map { $_->flag_id => $_ } @tracking_flags;
        $cache->{'tracking_flags'} = \%tracking_flags_hash;
    }
    return sort { $a->flag_type cmp $b->flag_type || $a->sortkey <=> $b->sortkey }
           values %{ $cache->{'tracking_flags'} };
}

sub remove_from_db {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    # Check to see if tracking_flags_bugs table has records
    if ($self->bug_count) {
        ThrowUserError('tracking_flag_has_contents', { flag => $self });
    }

    # Disable bug updates temporarily to avoid conflicts.
    SetParam('disable_bug_updates',  1);
    write_params();

    eval {
        $dbh->bz_start_transaction();

        $dbh->do('DELETE FROM bugs_activity WHERE fieldid = ?', undef, $self->id);
        $dbh->do('DELETE FROM fielddefs WHERE name = ?', undef, $self->name);

        $dbh->bz_commit_transaction();

        # Remove from request cache
        my $cache = Bugzilla->request_cache;
        if (exists $cache->{'tracking_flags'}) {
            delete $cache->{'tracking_flags'}->{$self->flag_id};
        }
    };
    my $error = "$@";
    SetParam('disable_bug_updates', 0);
    write_params();
    die $error if $error;
}

sub preload_all_the_things {
    my ($flags, $params) = @_;

    my %flag_hash = map { $_->flag_id => $_ } @$flags;
    my @flag_ids = keys %flag_hash;
    return unless @flag_ids;

    # Preload values
    my $value_objects
        = Bugzilla::Extension::TrackingFlags::Flag::Value->match({ tracking_flag_id => \@flag_ids });

    # Now populate the tracking flags with this set of value objects.
    foreach my $obj (@$value_objects) {
        my $flag_id = $obj->tracking_flag_id;

        # Prepopulate the tracking flag object in the value object
        $obj->{'tracking_flag'} = $flag_hash{$flag_id};

        # Prepopulate the current value objects for this tracking flag
        $flag_hash{$flag_id}->{'values'} ||= [];
        push(@{$flag_hash{$flag_id}->{'values'}}, $obj);
    }

    # Preload bug values if a bug_id is passed
    if ($params && exists $params->{'bug_id'} && $params->{'bug_id'}) {
        # We don't want to use @flag_ids here as we want all flags attached to this bug
        # even if they are inactive.
        my $bug_objects
            = Bugzilla::Extension::TrackingFlags::Flag::Bug->match({ bug_id => $params->{'bug_id'} });
        # Now populate the tracking flags with this set of objects.
        # Also we add them to the flag hash since we want them to be visible even if
        # they are not longer applicable to this product/component.
        foreach my $obj (@$bug_objects) {
            my $flag_id = $obj->tracking_flag_id;

            # Prepopulate the tracking flag object in the bug flag object
            $obj->{'tracking_flag'} = $flag_hash{$flag_id};

            # Prepopulate the the current bug flag object for the tracking flag
            $flag_hash{$flag_id}->{'bug_flag'} = $obj;
        }
    }

    @$flags = values %flag_hash;
}

###############################
####      Validators       ####
###############################

sub _check_name {
    my ($invocant, $name) = @_;
    $name = trim($name);
    $name || ThrowCodeError('param_required', { param => 'name' });
    return $name;
}

sub _check_description {
    my ($invocant, $description) = @_;
    $description = trim($description);
    $description || ThrowCodeError( 'param_required', { param => 'description' } );
    return $description;
}

sub _check_type {
    my ($invocant, $type) = @_;
    $type = trim($type);
    $type || ThrowCodeError( 'param_required', { param => 'type' } );
    grep($_->{name} eq $type, @{FLAG_TYPES()})
        || ThrowUserError('tracking_flags_invalid_flag_type', { type => $type });
    return $type;
}

sub _check_sortkey {
    my ($invocant, $sortkey) = @_;
    detaint_natural($sortkey)
        || ThrowUserError('field_invalid_sortkey', { sortkey => $sortkey });
    return $sortkey;
}

###############################
####       Setters         ####
###############################

sub set_name        { $_[0]->set('name', $_[1]);        }
sub set_description { $_[0]->set('description', $_[1]); }
sub set_type        { $_[0]->set('type', $_[1]);        }
sub set_sortkey     { $_[0]->set('sortkey', $_[1]);     }
sub set_is_active   { $_[0]->set('is_active', $_[1]);   }

###############################
####      Accessors        ####
###############################

sub flag_id     { return $_[0]->{'id'};          }
sub name        { return $_[0]->{'name'};        }
sub description { return $_[0]->{'description'}; }
sub flag_type   { return $_[0]->{'type'};        }
sub sortkey     { return $_[0]->{'sortkey'};     }
sub is_active   { return $_[0]->{'is_active'};   }

sub values {
    return $_[0]->{'values'} ||= Bugzilla::Extension::TrackingFlags::Flag::Value->match({
        tracking_flag_id => $_[0]->flag_id
    });
}

sub visibility {
    return $_[0]->{'visibility'} ||= Bugzilla::Extension::TrackingFlags::Flag::Visibility->match({
        tracking_flag_id => $_[0]->flag_id
    });
}

sub can_set_value {
    my ($self, $new_value, $user) = @_;
    $user ||= Bugzilla->user;
    my $new_value_obj;
    foreach my $value (@{$self->values}) {
        if ($value->value eq $new_value) {
            $new_value_obj = $value;
            last;
        }
    }
    return $new_value_obj && $user->in_group($new_value_obj->setter_group->name)
           ? 1
           : 0;
}

sub bug_flag {
    my ($self, $bug_id) = @_;
    # Return the current bug value object if defined unless the passed bug_id does
    # not equal the current bug value objects id.
    if (defined $self->{'bug_flag'}
        && (!$bug_id || $self->{'bug_flag'}->bug->id == $bug_id))
    {
        return $self->{'bug_flag'};
    }

    # Flag::Bug->new will return a default bug value object if $params undefined
    my $params = !$bug_id
                 ? undef
                 : { condition => "tracking_flag_id = ? AND bug_id = ?",
                     values    => [ $self->flag_id, $bug_id ] };
    return $self->{'bug_flag'} = Bugzilla::Extension::TrackingFlags::Flag::Bug->new($params);
}

sub bug_count {
    my ($self) = @_;
    return $self->{'bug_count'} if defined $self->{'bug_count'};
    my $dbh = Bugzilla->dbh;
    return $self->{'bug_count'} = scalar $dbh->selectrow_array("
        SELECT COUNT(bug_id)
          FROM tracking_flags_bugs
         WHERE tracking_flag_id = ?",
        undef, $self->flag_id);
}

sub activity_count {
    my ($self) = @_;
    return $self->{'activity_count'} if defined $self->{'activity_count'};
    my $dbh = Bugzilla->dbh;
    return $self->{'activity_count'} = scalar $dbh->selectrow_array("
        SELECT COUNT(bug_id)
          FROM bugs_activity
         WHERE fieldid = ?",
        undef, $self->id);
}

######################################
# Compatibility with Bugzilla::Field #
######################################

# Here we return 'field_id' instead of the real
# id as we want other Bugzilla code to treat this
# as a Bugzilla::Field object in certain places.
sub id                     { return $_[0]->{'field_id'};  }
sub type                   { return FIELD_TYPE_EXTENSION; }
sub legal_values           { return $_[0]->values;        }
sub custom                 { return 1;     }
sub in_new_bugmail         { return 1;     }
sub obsolete               { return 0;     }
sub enter_bug              { return 1;     }
sub buglist                { return 1;     }
sub is_select              { return 1;     }
sub is_abnormal            { return 1;     }
sub is_timetracking        { return 0;     }
sub visibility_field       { return undef; }
sub visibility_values      { return undef; }
sub controls_visibility_of { return undef; }
sub value_field            { return undef; }
sub controls_values_of     { return undef; }
sub is_visible_on_bug      { return 1;     }
sub is_relationship        { return 0;     }
sub reverse_desc           { return '';    }
sub is_mandatory           { return 0;     }
sub is_numeric             { return 0;     }

1;
