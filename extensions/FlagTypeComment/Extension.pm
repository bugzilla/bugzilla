# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the FlagTypeComment Bugzilla Extension.
#
# The Initial Developer of the Original Code is Alex Keybl 
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Alex Keybl <akeybl@mozilla.com>
#   byron jones <glob@mozilla.com>

package Bugzilla::Extension::FlagTypeComment;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::FlagTypeComment::Constants;

use Bugzilla::FlagType;
use Bugzilla::Util qw(trick_taint);
use Scalar::Util qw(blessed);

our $VERSION = '1';

################
# Installation #
################

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'flagtype_comments'} = {
        FIELDS => [
            type_id => {
                TYPE => 'SMALLINT(6)',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE  => 'flagtypes',
                    COLUMN => 'id',
                    DELETE => 'CASCADE'
                }
            },
            on_status => {
                TYPE => 'CHAR(1)',
                NOTNULL => 1
            },
            comment => {
                TYPE => 'MEDIUMTEXT',
                NOTNULL => 1
            }, 
        ],
        INDEXES => [
            flagtype_comments_idx => ['type_id'],
        ],
    };
}

#############
# Templates #
#############

sub template_before_process {
    my ($self, $args) = @_;
    my ($vars, $file) = @$args{qw(vars file)};

    return unless Bugzilla->user->id;
    if (grep { $_ eq $file } FLAGTYPE_COMMENT_TEMPLATES) {
        _set_ftc_states($file, $vars);
    }
}

sub _set_ftc_states {
    my ($file, $vars) = @_;
    my $dbh = Bugzilla->dbh;

    my $db_states;
    if ($file =~ /^admin\//) {
        # admin
        my $type = $vars->{'type'} || return;
        my ($target_type, $id);
        if (blessed($type)) {
            ($target_type, $id) = ($type->target_type, $type->id);
        } else {
            ($target_type, $id) = ($type->{target_type}, $type->{id});
            trick_taint($id);
        }
        if ($target_type eq 'bug') {
            return unless FLAGTYPE_COMMENT_BUG_FLAGS;
        } else {
            return unless FLAGTYPE_COMMENT_ATTACHMENT_FLAGS;
        }
        $db_states = $dbh->selectall_hashref(
            "SELECT type_id AS flagtype, on_status AS state, comment AS text
               FROM flagtype_comments WHERE type_id=?",
            'state',
            undef,
            $id);

    } else {
        # creating/editing attachment / viewing bug
        my $bug;
        if (exists $vars->{'bug'}) {
            $bug = $vars->{'bug'};
        } elsif (exists $vars->{'attachment'}) {
            $bug = $vars->{'attachment'}->{bug};
        } else {
            return;
        }

        my $flag_types = Bugzilla::FlagType::match({
            'target_type'  => ($file =~ /^bug/ ? 'bug' : 'attachment'),
            'product_id'   => $bug->product_id,
            'component_id' => $bug->component_id,
            'bug_id'       => $bug->id,
            'is_active'    => 1,
        });

        my $types = join(',', map { $_->id } @$flag_types);
        $db_states = $dbh->selectall_hashref(
            "SELECT type_id AS flagtype, on_status AS state, comment AS text
               FROM flagtype_comments WHERE type_id IN ($types)",
            'state');
    }

    my @edit_states;
    foreach my $state (FLAGTYPE_COMMENT_STATES) {
        if (exists $db_states->{$state}) {
            push @edit_states, $db_states->{$state};
        } else {
            push @edit_states, { state => $state, text => '' };
        }
    }
    $vars->{'ftc_states'} = \@edit_states;
}

#########
# Admin #
#########

sub flagtype_end_of_create {
    my ($self, $args) = @_;
    _set_flagtypes($args->{id});
}

sub flagtype_end_of_update {
    my ($self, $args) = @_;
    _set_flagtypes($args->{id});
}

sub _set_flagtypes {
    my $flagtype_id = shift;
    my $input = Bugzilla->input_params;
    my $dbh = Bugzilla->dbh;

    my $i = 0;
    foreach my $state (FLAGTYPE_COMMENT_STATES) {
        my $text = $input->{"ftc_text_$i"} || '';
        $text =~ s/\r\n/\n/g;
        trick_taint($text);

        if ($text ne '') {
            if ($dbh->selectrow_array(
                "SELECT 1 FROM flagtype_comments WHERE type_id=? AND on_status=?",
                undef,
                $flagtype_id, $state)
            ) {
                $dbh->do(
                    "UPDATE flagtype_comments SET comment=?
                      WHERE type_id=? AND on_status=?",
                    undef,
                    $text, $flagtype_id, $state);
            } else {
                $dbh->do(
                    "INSERT INTO flagtype_comments(type_id, on_status, comment)
                     VALUES (?, ?, ?)",
                    undef,
                    $flagtype_id, $state, $text);
            }

        } else {
            $dbh->do(
                "DELETE FROM flagtype_comments WHERE type_id=?  AND on_status=?",
                undef,
                $flagtype_id, $state);
        }
        $i++;
    }
}

__PACKAGE__->NAME;
