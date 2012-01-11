# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

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
use constant LIST_ORDER => 'id DESC';

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
    my $user_id = $search->user_id;

    # Enforce there only being SAVE_NUM_SEARCHES per user.
    my $min_id = $dbh->selectrow_array(
        'SELECT id FROM profile_search WHERE user_id = ? ORDER BY id DESC '
        . $dbh->sql_limit(1, SAVE_NUM_SEARCHES), undef, $user_id);
    if ($min_id) {
        $dbh->do('DELETE FROM profile_search WHERE user_id = ? AND id <= ?',
                 undef, ($user_id, $min_id));
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

sub check_quietly {
    my $class = shift;
    my $error_mode = Bugzilla->error_mode;
    Bugzilla->error_mode(ERROR_MODE_DIE);
    my $search = eval { $class->check(@_) };
    Bugzilla->error_mode($error_mode);
    return $search;
}

sub new_from_cookie {
    my ($invocant, $bug_ids) = @_;
    my $class = ref($invocant) || $invocant;

    my $search = { id       => 'cookie',
                   user_id  => Bugzilla->user->id,
                   bug_list => join(',', @$bug_ids) };

    bless $search, $class;
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

    my @bug_ids = ref($list) ? @$list : split(',', $list || '');
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
