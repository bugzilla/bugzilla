# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::FlagDefaultRequestee;

use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Error;
use Bugzilla::FlagType;
use Bugzilla::User;
use Bugzilla::Util 'trim';

use Bugzilla::Extension::FlagDefaultRequestee::Constants;

our $VERSION = '1';

################
# Installation #
################

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    $dbh->bz_add_column('flagtypes', 'default_requestee', {
        TYPE       => 'INT3',
        NOTNULL    => 0,
        REFERENCES => {  TABLE => 'profiles',
                        COLUMN => 'userid',
                        DELETE => 'SET NULL' }
    });
}

#############
# Templates #
#############

sub template_before_process {
    my ($self, $args) = @_;
    return unless Bugzilla->user->id;
    my ($vars, $file) = @$args{qw(vars file)};
    return unless grep { $_ eq $file } FLAGTYPE_TEMPLATES;

    my $flag_types = [];
    if (exists $vars->{bug} || exists $vars->{attachment}) {
        my $bug;
        if (exists $vars->{bug}) {
            $bug = $vars->{'bug'};
        } elsif (exists $vars->{'attachment'}) {
            $bug = $vars->{'attachment'}->{bug};
        }

        $flag_types = Bugzilla::FlagType::match({
            'target_type'  => ($file =~ /^bug/ ? 'bug' : 'attachment'),
            'product_id'   => $bug->product_id,
            'component_id' => $bug->component_id,
            'bug_id'       => $bug->id,
            'active_or_has_flags' => $bug->id,
        });

        $vars->{flag_currently_requested} ||= {};
        foreach my $type (@$flag_types) {
            my $flags = Bugzilla::Flag->match({
                type_id => $type->id, 
                bug_id  => $bug->id, 
                status  => '?'
            });
            map { $vars->{flag_currently_requested}->{$_->id} = 1 } @$flags;
        }
    }
    elsif ($file =~ /^bug\/create/ && exists $vars->{product}) {
        my $bug_flags        = $vars->{product}->flag_types->{bug};
        my $attachment_flags = $vars->{product}->flag_types->{attachment};
        $flag_types          = [ map { $_ } (@$bug_flags, @$attachment_flags) ];
    }

    return if !@$flag_types;

    $vars->{flag_default_requestees} ||= {};
    foreach my $type (@$flag_types) {
        next if !$type->default_requestee;
        $vars->{flag_default_requestees}->{$type->id} = $type->default_requestee->login;
    }
}

##################
# Object Methods #
##################

BEGIN {
    *Bugzilla::FlagType::default_requestee = \&_default_requestee;
}

sub object_columns {
    my ($self, $args) = @_;
    my ($class, $columns) = @$args{qw(class columns)};
    if ($class->isa('Bugzilla::FlagType')) {
        push(@$columns, 'default_requestee');
    }
}

sub object_update_columns {
    my ($self, $args) = @_;
    my $object = $args->{object};
    return unless $object->isa('Bugzilla::FlagType');

    my $columns = $args->{columns};
    push(@$columns, 'default_requestee');

    # editflagtypes.cgi doesn't call set_all, so we have to do this here
    my $input = Bugzilla->input_params;
    $object->set('default_requestee', $input->{default_requestee})
        if exists $input->{default_requestee};
}

sub object_validators {
    my ($self, $args) = @_;
    my $class = $args->{class};
    return unless $class->isa('Bugzilla::FlagType');

    my $validators = $args->{validators};
    $validators->{default_requestee} = \&_check_default_requestee;
}

sub object_before_create {
    my ($self, $args) = @_;
    my $class = $args->{class};
    return unless $class->isa('Bugzilla::FlagType');

    my $params = $args->{params};
    my $input = Bugzilla->input_params;
    $params->{default_requestee} = $input->{default_requestee}
        if exists $params->{default_requestee};
}

sub object_end_of_update {
    my ($self, $args) = @_;
    my $object = $args->{object};
    return unless $object->isa('Bugzilla::FlagType');

    my $old_object = $args->{old_object};
    my $changes = $args->{changes};
    my $old_id = $old_object->default_requestee
        ? $old_object->default_requestee->id
        : 0;
    my $new_id = $object->default_requestee
        ? $object->default_requestee->id
        : 0;
    return if $old_id == $new_id;

    $changes->{default_requestee} = [ $old_id, $new_id ];
}

sub _check_default_requestee {
    my ($self, $value, $field) = @_;
    $value = trim($value // '');
    return undef if $value eq '';
    ThrowUserError("flag_default_requestee_review")
        if $self->name eq 'review';
    return Bugzilla::User->check($value)->id;
}

sub _default_requestee {
    my ($self) = @_;
    return $self->{default_requestee}
        ? Bugzilla::User->new({ id => $self->{default_requestee}, cache => 1 })
        : undef;
}

__PACKAGE__->NAME;
