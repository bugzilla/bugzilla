# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TrackingFlags::Flag::Bug;

use base qw(Bugzilla::Object);

use strict;
use warnings;

use Bugzilla::Extension::TrackingFlags::Flag;

use Bugzilla::Bug;
use Bugzilla::Error;

use Scalar::Util qw(blessed);

###############################
####    Initialization     ####
###############################

use constant DEFAULT_FLAG_BUG => {
    'id'               => 0,
    'tracking_flag_id' => 0,
    'bug_id'           => '',
    'value'            => '---',
};

use constant DB_TABLE => 'tracking_flags_bugs';

use constant DB_COLUMNS => qw(
    id
    tracking_flag_id
    bug_id
    value
);

use constant LIST_ORDER => 'id';

use constant UPDATE_COLUMNS => qw(
    value
);

use constant VALIDATORS => {
    tracking_flag_id => \&_check_tracking_flag,
    value            => \&_check_value,
};

use constant AUDIT_CREATES => 0;
use constant AUDIT_UPDATES => 0;
use constant AUDIT_REMOVES => 0;

###############################
####    Object Methods     ####
###############################

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my ($param) = @_;

    my $self;
    if ($param) {
        $self = $class->SUPER::new(@_);
        if (!$self) {
            $self = DEFAULT_FLAG_BUG;
            bless($self, $class);
        }
    }
    else {
        $self = DEFAULT_FLAG_BUG;
        bless($self, $class);
    }

    return $self
}

sub match {
    my $class = shift;
    my $bug_flags = $class->SUPER::match(@_);
    preload_all_the_things($bug_flags);
    return $bug_flags;
}

sub remove_from_db {
    my ($self) = @_;
    $self->SUPER::remove_from_db();
    $self->{'id'} = $self->{'tracking_flag_id'} = $self->{'bug_id'} = 0;
    $self->{'value'} = '---';
}

sub preload_all_the_things {
    my ($bug_flags) = @_;
    my $cache = Bugzilla->request_cache;

    # Preload tracking flag objects
    my @tracking_flag_ids;
    foreach my $bug_flag (@$bug_flags) {
        if (exists $cache->{'tracking_flags'}
            && $cache->{'tracking_flags'}->{$bug_flag->tracking_flag_id})
        {
            $bug_flag->{'tracking_flag'}
                = $cache->{'tracking_flags'}->{$bug_flag->tracking_flag_id};
            next;
        }
        push(@tracking_flag_ids, $bug_flag->tracking_flag_id);
    }

    return unless @tracking_flag_ids;

    my $tracking_flags
        = Bugzilla::Extension::TrackingFlags::Flag->match({ id => \@tracking_flag_ids });
    my %tracking_flag_hash = map { $_->flag_id => $_ } @$tracking_flags;

    foreach my $bug_flag (@$bug_flags) {
        next if exists $bug_flag->{'tracking_flag'};
        $bug_flag->{'tracking_flag'} = $tracking_flag_hash{$bug_flag->tracking_flag_id};
    }
}

##############################
####    Class Methods     ####
##############################

sub update_all_values {
    my ($invocant, $params) = @_;
    my $dbh = Bugzilla->dbh;
    $dbh->do(
        "UPDATE tracking_flags_bugs SET value=? WHERE tracking_flag_id=? AND value=?",
        undef,
        $params->{new_value},
        $params->{value_obj}->tracking_flag_id,
        $params->{old_value},
    );
}

###############################
####      Validators       ####
###############################

sub _check_value {
    my ($invocant, $value) = @_;
    $value || ThrowCodeError('param_required', { param => 'value' });
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

###############################
####       Setters         ####
###############################

sub set_value { $_[0]->set('value', $_[1]); }

###############################
####      Accessors        ####
###############################

sub tracking_flag_id { return $_[0]->{'tracking_flag_id'}; }
sub bug_id           { return $_[0]->{'bug_id'};           }
sub value            { return $_[0]->{'value'};            }

sub bug {
    return $_[0]->{'bug'} ||= Bugzilla::Bug->new({
        id => $_[0]->bug_id, cache => 1
    });
}

sub tracking_flag {
    return $_[0]->{'tracking_flag'} ||= Bugzilla::Extension::TrackingFlags::Flag->new({
        id => $_[0]->tracking_flag_id, cache => 1
    });
}

1;
