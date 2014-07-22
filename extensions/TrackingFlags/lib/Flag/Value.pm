# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TrackingFlags::Flag::Value;

use base qw(Bugzilla::Object);

use strict;
use warnings;

use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::Util qw(detaint_natural trim);
use Scalar::Util qw(blessed);

###############################
####    Initialization     ####
###############################

use constant DB_TABLE => 'tracking_flags_values';

use constant DB_COLUMNS => qw(
    id
    tracking_flag_id
    setter_group_id
    value
    sortkey
    is_active
    comment
);

use constant LIST_ORDER => 'sortkey';

use constant UPDATE_COLUMNS => qw(
    setter_group_id
    value
    sortkey
    is_active
    comment
);

use constant VALIDATORS => {
    tracking_flag_id => \&_check_tracking_flag,
    setter_group_id  => \&_check_setter_group,
    value            => \&_check_value,
    sortkey          => \&_check_sortkey,
    is_active        => \&Bugzilla::Object::check_boolean,
    comment          => \&_check_comment,
};

###############################
####      Validators       ####
###############################

sub _check_value {
    my ($invocant, $value) = @_;
    defined $value || ThrowCodeError('param_required', { param => 'value' });
    return $value;
}

sub _check_tracking_flag {
    my ($invocant, $flag) = @_;
    if (blessed $flag) {
        return $flag->flag_id;
    }
    $flag = Bugzilla::Extension::TrackingFlags::Flag->new({ id => $flag, cache => 1 })
        || ThrowCodeError('tracking_flags_invalid_param', { name => 'flag_id', value => $flag });
    return $flag->flag_id;
}

sub _check_setter_group {
    my ($invocant, $group) = @_;
    if (blessed $group) {
        return $group->id;
    }
    $group = Bugzilla::Group->new({ id => $group, cache => 1 })
        || ThrowCodeError('tracking_flags_invalid_param', { name => 'setter_group_id', value => $group });
    return $group->id;
}

sub _check_sortkey {
    my ($invocant, $sortkey) = @_;
    detaint_natural($sortkey)
        || ThrowUserError('field_invalid_sortkey', { sortkey => $sortkey });
    return $sortkey;
}

sub _check_comment {
    my ($invocant, $value) = @_;
    return undef unless defined $value;
    $value = trim($value);
    return $value eq '' ? undef : $value;
}

###############################
####       Setters         ####
###############################

sub set_setter_group_id { $_[0]->set('setter_group_id', $_[1]); }
sub set_value           { $_[0]->set('value', $_[1]);           }
sub set_sortkey         { $_[0]->set('sortkey', $_[1]);         }
sub set_is_active       { $_[0]->set('is_active', $_[1]);       }
sub set_comment         { $_[0]->set('comment', $_[1]);         }

###############################
####      Accessors        ####
###############################

sub tracking_flag_id { return $_[0]->{'tracking_flag_id'}; }
sub setter_group_id  { return $_[0]->{'setter_group_id'};  }
sub value            { return $_[0]->{'value'};            }
sub sortkey          { return $_[0]->{'sortkey'};          }
sub is_active        { return $_[0]->{'is_active'};        }
sub comment          { return $_[0]->{'comment'};          }

sub tracking_flag {
    return $_[0]->{'tracking_flag'} ||= Bugzilla::Extension::TrackingFlags::Flag->new({
        id => $_[0]->tracking_flag_id, cache => 1
    });
}

sub setter_group {
    if ($_[0]->setter_group_id) {
        $_[0]->{'setter_group'} ||= Bugzilla::Group->new({
            id => $_[0]->setter_group_id, cache => 1
        });
    }
    return $_[0]->{'setter_group'};
}

########################################
## Compatibility with Bugzilla::Field ##
########################################

sub name              { return $_[0]->{'value'}; }
sub is_visible_on_bug { return 1;                }

1;
