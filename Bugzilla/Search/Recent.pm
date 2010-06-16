# -*- Mode: perl; indent-tabs-mode: nil -*-
#
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
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Search::Recent;
use strict;
use base qw(Bugzilla::Object);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util;

#############
# Constants #
#############

use constant DB_TABLE => 'profile_search';
use constant LIST_ORDER => 'id';

use constant REQUIRED_CREATE_FIELDS => ();

use constant DB_COLUMNS => qw(
    id
    user_id
    bug_list
    list_order
);

use constant VALIDATORS => {
    user_id    => \&_check_user_id,
    bug_list   => \&_check_bug_list,
    list_order => \&_check_list_order,
};

use constant UPDATE_COLUMNS => qw(bug_list list_order);

###################
# DB Manipulation #
###################

sub create {
    my $class = shift;
    my $dbh = Bugzilla->dbh;
    $dbh->bz_start_transaction();
    my $search = $class->SUPER::create(@_);   

    # Enforce there only being SAVE_NUM_SEARCHES per user.
    my ($num_searches, $min_id) = $dbh->selectrow_array(
        'SELECT COUNT(*), MIN(id) FROM profile_search WHERE user_id = ?',
        undef, $search->user_id);
    if ($num_searches > SAVE_NUM_SEARCHES) {
        $dbh->do('DELETE FROM profile_search WHERE id = ?', undef, $min_id);
    }
    $dbh->bz_commit_transaction();
    return $search;
}

sub create_placeholder {
    my $class = shift;
    return $class->create({ user_id  => Bugzilla->user->id,
                            bug_list => '' });
}

###############
# Constructor #
###############

sub check {
    my $class = shift;
    my $search = $class->SUPER::check(@_);
    my $user = Bugzilla->user;
    if ($search->user_id != $user->id) {
        ThrowUserError('object_does_not_exist', { id => $search->id });
    }
    return $search;
}

####################
# Simple Accessors #
####################

sub bug_list   { return [split(',', $_[0]->{'bug_list'})]; }
sub list_order { return $_[0]->{'list_order'}; }
sub user_id    { return $_[0]->{'user_id'}; }

############
# Mutators #
############

sub set_bug_list   { $_[0]->set('bug_list',   $_[1]); }
sub set_list_order { $_[0]->set('list_order', $_[1]); }

##############
# Validators #
##############

sub _check_user_id {
    my ($invocant, $id) = @_;
    require Bugzilla::User;
    return Bugzilla::User->check({ id => $id })->id;
}

sub _check_bug_list {
    my ($invocant, $list) = @_;

    my @bug_ids = ref($list) ? @$list : split(',', $list);
    detaint_natural($_) foreach @bug_ids;
    return join(',', @bug_ids);
}

sub _check_list_order { defined $_[1] ? trim($_[1]) : '' }

1;

__END__

=head1 NAME

Bugzilla::Search::Recent - A search recently run by a logged-in user.

=head1 SYNOPSIS

 use Bugzilla::Search::Recent;


=head1 DESCRIPTION

This is an implementation of L<Bugzilla::Object>, and so has all the
same methods available as L<Bugzilla::Object>, in addition to what is
documented below.
