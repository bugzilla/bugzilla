# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::WebService::Group;

use 5.10.1;
use strict;

use parent qw(Bugzilla::WebService);
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::WebService::Util qw(validate translate params_to_objects);

use constant MAPPED_RETURNS => {
    userregexp => 'user_regexp',
    isactive => 'is_active'
};

sub create {
    my ($self, $params) = @_;

    Bugzilla->login(LOGIN_REQUIRED);
    Bugzilla->user->in_group('creategroups') 
        || ThrowUserError("auth_failure", { group  => "creategroups",
                                            action => "add",
                                            object => "group"});
    # Create group
    my $group = Bugzilla::Group->create({
        name               => $params->{name},
        description        => $params->{description},
        userregexp         => $params->{user_regexp},
        isactive           => $params->{is_active},
        isbuggroup         => 1,
        icon_url           => $params->{icon_url}
    });
    return { id => $self->type('int', $group->id) };
}

sub update {
    my ($self, $params) = @_;

    my $dbh = Bugzilla->dbh;

    Bugzilla->login(LOGIN_REQUIRED);
    Bugzilla->user->in_group('creategroups')
        || ThrowUserError("auth_failure", { group  => "creategroups",
                                            action => "edit",
                                            object => "group" });

    defined($params->{names}) || defined($params->{ids})
        || ThrowCodeError('params_required',
               { function => 'Group.update', params => ['ids', 'names'] });

    my $group_objects = params_to_objects($params, 'Bugzilla::Group');

    my %values = %$params;
    
    # We delete names and ids to keep only new values to set.
    delete $values{names};
    delete $values{ids};

    $dbh->bz_start_transaction();
    foreach my $group (@$group_objects) {
        $group->set_all(\%values);
    }

    my %changes;
    foreach my $group (@$group_objects) {
        my $returned_changes = $group->update();
        $changes{$group->id} = translate($returned_changes, MAPPED_RETURNS);
    }
    $dbh->bz_commit_transaction();

    my @result;
    foreach my $group (@$group_objects) {
        my %hash = (
            id      => $group->id,
            changes => {},
        );
        foreach my $field (keys %{ $changes{$group->id} }) {
            my $change = $changes{$group->id}->{$field};
            $hash{changes}{$field} = {
                removed => $self->type('string', $change->[0]),
                added   => $self->type('string', $change->[1]) 
            };
        }
       push(@result, \%hash);
    }

    return { groups => \@result };
}

1;

__END__

=head1 NAME

Bugzilla::Webservice::Group - The API for creating, changing, and getting
information about Groups.

=head1 DESCRIPTION

This part of the Bugzilla API allows you to create Groups and
get information about them.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed,
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.

Although the data input and output is the same for JSONRPC, XMLRPC and REST,
the directions for how to access the data via REST is noted in each method
where applicable.

=head1 Group Creation and Modification

=head2 create

B<UNSTABLE>

=over

=item B<Description>

This allows you to create a new group in Bugzilla.

=item B<REST>

POST /group

The params to include in the POST body as well as the returned data format,
are the same as below.

=item B<Params>

Some params must be set, or an error will be thrown. These params are
marked B<Required>.

=over

=item C<name>

B<Required> C<string> A short name for this group. Must be unique. This
is not usually displayed in the user interface, except in a few places.

=item C<description>

B<Required> C<string> A human-readable name for this group. Should be
relatively short. This is what will normally appear in the UI as the
name of the group.

=item C<user_regexp>

C<string> A regular expression. Any user whose Bugzilla username matches
this regular expression will automatically be granted membership in this group.

=item C<is_active>

C<boolean> C<True> if new group can be used for bugs, C<False> if this
is a group that will only contain users and no bugs will be restricted
to it.

=item C<icon_url>

C<string> A URL pointing to a small icon used to identify the group.
This icon will show up next to users' names in various parts of Bugzilla
if they are in this group.

=back

=item B<Returns>

A hash with one element, C<id>. This is the id of the newly-created group.

=item B<Errors>

=over

=item 800 (Empty Group Name)

You must specify a value for the C<name> field.

=item 801 (Group Exists)

There is already another group with the same C<name>.

=item 802 (Group Missing Description)

You must specify a value for the C<description> field.

=item 803 (Group Regexp Invalid)

You specified an invalid regular expression in the C<user_regexp> field.

=back

=item B<History>

=over

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=head2 update

B<UNSTABLE>

=over

=item B<Description>

This allows you to update a group in Bugzilla.

=item B<REST>

PUT /group/<group_name_or_id>

The params to include in the PUT body as well as the returned data format,
are the same as below. The C<ids> param will be overridden as it is pulled
from the URL path.

=item B<Params>

At least C<ids> or C<names> must be set, or an error will be thrown.

=over

=item C<ids>

B<Required> C<array> Contain ids of groups to update.

=item C<names>

B<Required> C<array> Contain names of groups to update.

=item C<name>

C<string> A new name for group.

=item C<description>

C<string> A new description for groups. This is what will appear in the UI
as the name of the groups.

=item C<user_regexp>

C<string> A new regular expression for email. Will automatically grant
membership to these groups to anyone with an email address that matches
this perl regular expression.

=item C<is_active>

C<boolean> Set if groups are active and eligible to be used for bugs.
True if bugs can be restricted to this group, false otherwise.

=item C<icon_url>

C<string> A URL pointing to an icon that will appear next to the name of
users who are in this group.

=back

=item B<Returns>

A C<hash> with a single field "groups". This points to an array of hashes
with the following fields:

=over

=item C<id>

C<int> The id of the group that was updated.

=item C<changes>

C<hash> The changes that were actually done on this group. The keys are
the names of the fields that were changed, and the values are a hash
with two keys:

=over

=item C<added>

C<string> The values that were added to this field,
possibly a comma-and-space-separated list if multiple values were added.

=item C<removed>

C<string> The values that were removed from this field, possibly a
comma-and-space-separated list if multiple values were removed.

=back

=back

=item B<Errors>

The same as L</create>.

=item B<History>

=over

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=cut
