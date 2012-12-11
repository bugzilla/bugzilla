# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with the
# License. You may obtain a copy of the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis, 
# WITHOUT WARRANTY OF ANY KIND,  either express or implied. See the License for
# the specific language governing rights and limitations under the License.
#
# The Original Code is the BMO Bugzilla Extension.
#
# The Initial Developer of the Original Code is Mozilla Foundation.  Portions created
# by the Initial Developer are Copyright (C) 2011 the Mozilla Foundation. All
# Rights Reserved.
#
# Contributor(s):
#   Dave Lawrence <dkl@mozilla.com>

package Bugzilla::Extension::BMO::WebService;

use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util qw(detaint_natural trick_taint);
use Bugzilla::WebService::Util qw(validate);
use Bugzilla::Field;

sub getBugsConfirmer {
    my ($self, $params) = validate(@_, 'names');
    my $dbh = Bugzilla->dbh;

    defined($params->{names}) 
        || ThrowCodeError('params_required',
               { function => 'BMO.getBugsConfirmer', params => ['names'] });

    my @user_objects = map { Bugzilla::User->check($_) } @{ $params->{names} };

    # start filtering to remove duplicate user ids
    @user_objects = values %{{ map { $_->id => $_ } @user_objects }};

    my $fieldid = get_field_id('bug_status');

    my $query = "SELECT DISTINCT bugs_activity.bug_id
                   FROM bugs_activity
                        LEFT JOIN bug_group_map 
                        ON bugs_activity.bug_id = bug_group_map.bug_id
                  WHERE bugs_activity.fieldid = ?
                        AND bugs_activity.added = 'NEW'
                        AND bugs_activity.removed = 'UNCONFIRMED'
                        AND bugs_activity.who = ?
                        AND bug_group_map.bug_id IS NULL
               ORDER BY bugs_activity.bug_id";

    my %users;
    foreach my $user (@user_objects) {
        my $bugs = $dbh->selectcol_arrayref($query, undef, $fieldid, $user->id);
        $users{$user->login} = $bugs;
    }

    return \%users;
}

sub getBugsVerifier {
    my ($self, $params) = validate(@_, 'names');
    my $dbh = Bugzilla->dbh;

    defined($params->{names}) 
        || ThrowCodeError('params_required',
               { function => 'BMO.getBugsVerifier', params => ['names'] });

    my @user_objects = map { Bugzilla::User->check($_) } @{ $params->{names} };

    # start filtering to remove duplicate user ids
    @user_objects = values %{{ map { $_->id => $_ } @user_objects }};

    my $fieldid = get_field_id('bug_status');

    my $query = "SELECT DISTINCT bugs_activity.bug_id
                   FROM bugs_activity
                        LEFT JOIN bug_group_map 
                        ON bugs_activity.bug_id = bug_group_map.bug_id
                  WHERE bugs_activity.fieldid = ?
                        AND bugs_activity.removed = 'RESOLVED'
                        AND bugs_activity.added = 'VERIFIED'
                        AND bugs_activity.who = ?
                        AND bug_group_map.bug_id IS NULL
               ORDER BY bugs_activity.bug_id";

    my %users;
    foreach my $user (@user_objects) {
        my $bugs = $dbh->selectcol_arrayref($query, undef, $fieldid, $user->id);
        $users{$user->login} = $bugs;
    }

    return \%users;
}

sub prod_comp_search {
    my ($self, $params) = @_;
    my $user = Bugzilla->user;
    my $dbh = Bugzilla->switch_to_shadow_db();

    my $search = $params->{'search'};
    $search || ThrowCodeError('param_required',
        { function => 'Bug.prod_comp_search', param => 'search' });

    my $limit = detaint_natural($params->{'limit'}) 
                ? $dbh->sql_limit($params->{'limit'}) 
                : '';

    # We do this in the DB directly as we want it to be fast and
    # not have the overhead of loading full product objects
 
    # All products which the user has "Entry" access to.
    my $enterable_ids = $dbh->selectcol_arrayref(
           'SELECT products.id FROM products
         LEFT JOIN group_control_map
                   ON group_control_map.product_id = products.id
                      AND group_control_map.entry != 0
                      AND group_id NOT IN (' . $user->groups_as_string . ')
            WHERE group_id IS NULL
                  AND products.isactive = 1');

    if (scalar @$enterable_ids) {
        # And all of these products must have at least one component
        # and one version.
        $enterable_ids = $dbh->selectcol_arrayref(
            'SELECT DISTINCT products.id FROM products
              WHERE ' . $dbh->sql_in('products.id', $enterable_ids) .
              ' AND products.id IN (SELECT DISTINCT components.product_id
                                      FROM components
                                     WHERE components.isactive = 1)
                AND products.id IN (SELECT DISTINCT versions.product_id
                                      FROM versions
                                     WHERE versions.isactive = 1)');
    }

    return { products => [] } if !scalar @$enterable_ids;

    my @list;
    foreach my $word (split(/[\s,]+/, $search)) {
        if ($word ne "") {
            my $sql_word = $dbh->quote($word);
            trick_taint($sql_word);
            # XXX CONCAT_WS is MySQL specific
            my $field = "CONCAT_WS(' ', products.name, components.name, components.description)";
            push(@list, $dbh->sql_iposition($sql_word, $field) . " > 0");
        }
    }

    my $products = $dbh->selectall_arrayref("
        SELECT products.name AS product,
               components.name AS component
          FROM products 
               INNER JOIN components ON products.id = components.product_id
         WHERE (" . join(" AND ", @list) . ")
               AND products.id IN (" . join(",", @$enterable_ids) . ")
      ORDER BY products.name $limit", 
        { Slice => {} });

    # To help mozilla staff file bmo administration bugs into the right
    # component, sort bmo in front of bugzilla.
    if ($user->in_group('mozilla-corporation') || $user->in_group('mozilla-foundation')) {
        $products = [
            sort {
                return 1 if $a->{product} eq 'Bugzilla'
                            && $b->{product} eq 'bugzilla.mozilla.org';
                return -1 if $b->{product} eq 'Bugzilla'
                             && $a->{product} eq 'bugzilla.mozilla.org';
                return lc($a->{product}) cmp lc($b->{product})
                       || lc($a->{component}) cmp lc($b->{component});
            } @$products
        ];
    }

    return { products => $products };
}

1;

__END__

=head1 NAME

Bugzilla::Extension::BMO::Webservice - The BMO WebServices API

=head1 DESCRIPTION

This module contains API methods that are useful to user's of bugzilla.mozilla.org.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed, 
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.

=head2 getBugsConfirmer

B<UNSTABLE>

=over

=item B<Description>

This method returns public bug ids that a given user has confirmed (changed from 
C<UNCONFIRMED> to C<NEW>).

=item B<Params>

You pass a field called C<names> that is a list of Bugzilla login names to find bugs for.

=over

=item C<names> (array) - An array of strings representing Bugzilla login names. 

=back

=item B<Returns>

=over

A hash of Bugzilla login names. Each name points to an array of bug ids that the user has confirmed.

=back

=item B<Errors>

=over

=back

=item B<History>

=over

=item Added in BMO Bugzilla B<4.0>.

=back

=back

=head2 getBugsVerifier

B<UNSTABLE>

=over

=item B<Description>

This method returns public bug ids that a given user has verified (changed from
C<RESOLVED> to C<VERIFIED>). 

=item B<Params>

You pass a field called C<names> that is a list of Bugzilla login names to find bugs for.

=over

=item C<names> (array) - An array of strings representing Bugzilla login names. 

=back

=item B<Returns>

=over

A hash of Bugzilla login names. Each name points to an array of bug ids that the user has verified.

=back

=item B<Errors>

=over

=back

=item B<History>

=over

=item Added in BMO Bugzilla B<4.0>.

=back

=back
