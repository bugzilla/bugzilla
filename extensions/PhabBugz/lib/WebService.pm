# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::WebService;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::BugMail;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Util qw(correct_urlbase detaint_natural);
use Bugzilla::WebService::Constants;

use Bugzilla::Extension::PhabBugz::Util qw(
    create_revision_attachment
    create_private_revision_policy
    edit_revision_policy
    get_bug_role_phids
    get_project_phid
    get_revisions_by_ids
    intersect
    make_revision_public
    request
);

use Data::Dumper;

use constant PUBLIC_METHODS => qw(
    revision
);

sub revision {
    my ($self, $params) = @_;

    unless (defined $params->{revision} && detaint_natural($params->{revision})) {
        ThrowCodeError('param_required', { param => 'revision' })
    }

    my $user = Bugzilla->set_user(Bugzilla::User->new({ name => 'conduit@mozilla.bugs' }));

    # Obtain more information about the revision from Phabricator
    my $revision_id = $params->{revision};
    my $revisions = get_revisions_by_ids([$revision_id]);
    my $revision = $revisions->[0];

    my $revision_phid  = $revision->{phid};
    my $revision_title = $revision->{fields}{title} || 'Unknown Description';
    my $bug_id         = $revision->{fields}{'bugzilla.bug-id'};

    my $bug = Bugzilla::Bug->check($bug_id);

    # If bug is public then remove privacy policy
    my $result;
    if (!@{ $bug->groups_in }) {
        $result = make_revision_public($revision_id);
    }
    # Else bug is private
    else {
        my $phab_sync_groups = Bugzilla->params->{phabricator_sync_groups}
            || ThrowUserError('invalid_phabricator_sync_groups');
        my $sync_group_names = [ split('[,\s]+', $phab_sync_groups) ];

        my $bug_groups = $bug->groups_in;
        my $bug_group_names = [ map { $_->name } @$bug_groups ];

        my @set_groups = intersect($bug_group_names, $sync_group_names);

        # If bug privacy groups do not have any matching synchronized groups,
        # then leave revision private and it will have be dealt with manually.
        if (!@set_groups) {
            ThrowUserError('invalid_phabricator_sync_groups');
        }

        my $policy_phid = create_private_revision_policy($bug, \@set_groups);
        my $subscribers = get_bug_role_phids($bug);
        $result = edit_revision_policy($revision_phid, $policy_phid, $subscribers);
    }

    my $attachment = create_revision_attachment($bug, $revision_id, $revision_title);

    Bugzilla::BugMail::Send($bug_id, { changer => $user });

    return {
        result          => $result,
        attachment_id   => $attachment->id,
        attachment_link => correct_urlbase() . "attachment.cgi?id=" . $attachment->id
    };
}

sub rest_resources {
    return [
        qr{^/phabbugz/revision/([^/]+)$}, {
            POST => {
                method => 'revision',
                params => sub {
                    return { revision => $_[0] };
                }
            }
        }
    ];
}

1;
