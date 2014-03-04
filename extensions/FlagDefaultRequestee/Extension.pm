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

use Bugzilla::Extension::FlagDefaultRequestee::Constants;

our $VERSION = '1';

################
# Installation #
################

sub install_update_db {
    my $dbh = Bugzilla->dbh;
    if (!$dbh->bz_column_info('flagtypes', 'default_requestee')) {
        $dbh->bz_add_column('flagtypes', 'default_requestee', {
            TYPE => 'INT3', NOTNULL => 0,
            REFERENCES => { TABLE  => 'profiles',
                            COLUMN => 'userid',
                            DELETE => 'SET NULL' }
        });
    }
}

#############
# Templates #
#############

sub template_before_process {
    my ($self, $args) = @_;
    my ($vars, $file) = @$args{qw(vars file)};
    my $dbh = Bugzilla->dbh;

    return unless Bugzilla->user->id;

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

    $vars->{flag_default_requestees}  ||= {};
    foreach my $type (@$flag_types) {
        next if !$type->default_requestee;
        $vars->{flag_default_requestees}->{$type->id} = $type->default_requestee->login;
    }
}

#########
# Admin #
#########

sub flagtype_end_of_create {
    my ($self, $args) = @_;
    _set_default_requestee($args->{type});
}

sub flagtype_end_of_update {
    my ($self, $args) = @_;
    _set_default_requestee($args->{type});
}

sub _set_default_requestee {
    my $type  = shift;
    my $input = Bugzilla->input_params;
    my $dbh   = Bugzilla->dbh;

    my $requestee_login = $input->{'default_requestee'};

    my $requestee_id = undef;
    if ($requestee_login) {
        if ($type->name eq 'review') {
            ThrowUserError("flag_default_requestee_review");
        }
        my $requestee = Bugzilla::User->check($requestee_login);
        $requestee_id = $requestee->id;
    }

    $dbh->do("UPDATE flagtypes SET default_requestee = ? WHERE id = ?",
             undef, $requestee_id, $type->id);
    Bugzilla->memcached->clear({ table => 'flagtypes', id => $type->id });
}

##################
# Object Methods #
##################

BEGIN {
    *Bugzilla::FlagType::default_requestee = \&_default_requestee;
}

sub _default_requestee {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    return $self->{default_requestee} if exists $self->{default_requestee};
    my $requestee_id = $dbh->selectrow_array("SELECT default_requestee
                                                FROM flagtypes
                                               WHERE id = ?", 
                                             undef, $self->id);
    $self->{default_requestee} = $requestee_id 
                                 ? Bugzilla::User->new($requestee_id)
                                 : undef;
    return $self->{default_requestee};
}

__PACKAGE__->NAME;
