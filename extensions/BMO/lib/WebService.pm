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

=item B<History>

=over

=item Added in BMO Bugzilla B<4.0>.

=back

=back
