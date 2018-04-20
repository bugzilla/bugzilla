# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Util;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Util qw(trim);
use Bugzilla::Extension::PhabBugz::Constants;

use JSON::XS qw(encode_json decode_json);
use List::Util qw(first);
use LWP::UserAgent;
use Taint::Util qw(untaint);

use base qw(Exporter);

our @EXPORT_OK = qw(
    add_comment_to_revision
    add_security_sync_comments
    create_private_revision_policy
    create_project
    create_revision_attachment
    edit_revision_policy
    get_attachment_revisions
    get_bug_role_phids
    get_members_by_bmo_id
    get_members_by_phid
    get_needs_review
    get_phab_bmo_ids
    get_project_phid
    get_revisions_by_ids
    get_revisions_by_phids
    get_security_sync_groups
    intersect
    is_attachment_phab_revision
    make_revision_private
    make_revision_public
    request
    set_phab_user
    set_project_members
    set_revision_subscribers
);

sub get_revisions_by_ids {
    my ($ids) = @_;
    return _get_revisions({ ids => $ids });
}

sub get_revisions_by_phids {
    my ($phids) = @_;
    return _get_revisions({ phids => $phids });
}

sub _get_revisions {
    my ($constraints) = @_;

    my $data = {
        queryKey    => 'all',
        constraints => $constraints
    };

    my $result = request('differential.revision.search', $data);

    ThrowUserError('invalid_phabricator_revision_id')
        unless (exists $result->{result}{data} && @{ $result->{result}{data} });

    return $result->{result}{data};
}

sub create_revision_attachment {
    my ( $bug, $revision, $timestamp ) = @_;

    my $phab_base_uri = Bugzilla->params->{phabricator_base_uri};
    ThrowUserError('invalid_phabricator_uri') unless $phab_base_uri;

    my $revision_uri = $phab_base_uri . "D" . $revision->id;

    # Check for previous attachment with same revision id.
    # If one matches then return it instead. This is fine as
    # BMO does not contain actual diff content.
    my @review_attachments = grep { is_attachment_phab_revision($_) } @{ $bug->attachments };
    my $review_attachment = first { trim($_->data) eq $revision_uri } @review_attachments;
    return $review_attachment if defined $review_attachment;

    # No attachment is present, so we can now create new one

    if (!$timestamp) {
        ($timestamp) = Bugzilla->dbh->selectrow_array("SELECT NOW()");
    }

    my $attachment = Bugzilla::Attachment->create(
        {
            bug         => $bug,
            creation_ts => $timestamp,
            data        => $revision_uri,
            description => $revision->title,
            filename    => 'phabricator-D' . $revision->id . '-url.txt',
            ispatch     => 0,
            isprivate   => 0,
            mimetype    => PHAB_CONTENT_TYPE,
        }
    );

    # Insert a comment about the new attachment into the database.
    $bug->add_comment($revision->summary, { type       => CMT_ATTACHMENT_CREATED,
                                            extra_data => $attachment->id });

    return $attachment;
}

sub intersect {
    my ($list1, $list2) = @_;
    my %e = map { $_ => undef } @{$list1};
    return grep { exists( $e{$_} ) } @{$list2};
}

sub get_bug_role_phids {
    my ($bug) = @_;

    my @bug_users = ( $bug->reporter );
    push(@bug_users, $bug->assigned_to)
        if $bug->assigned_to->email !~ /^nobody\@mozilla\.org$/;
    push(@bug_users, $bug->qa_contact) if $bug->qa_contact;
    push(@bug_users, @{ $bug->cc_users }) if @{ $bug->cc_users };

    return get_members_by_bmo_id(\@bug_users);
}

sub create_private_revision_policy {
    my ( $groups ) = @_;

    my $data = {
        objectType => 'DREV',
        default    => 'deny',
        policy     => [
            {
                action => 'allow',
                rule   => 'PhabricatorSubscriptionsSubscribersPolicyRule'
            },
            {
                action => 'allow',
                rule   => 'PhabricatorDifferentialReviewersPolicyRule'
            }
        ]
    };

    if(scalar @$groups gt 0) {
        my $project_phids = [];
        foreach my $group (@$groups) {
            my $phid = get_project_phid('bmo-' . $group);
            push(@$project_phids, $phid) if $phid;
        }

        ThrowUserError('invalid_phabricator_sync_groups') unless @$project_phids;

        push(@{ $data->{policy} },
            {
                action => 'allow',
                rule   => 'PhabricatorProjectsPolicyRule',
                value  => $project_phids,
            }
        );
    }
    else {
        my $secure_revision = Bugzilla::Extension::PhabBugz::Project->new_from_query({
            name => 'secure-revision'
        });
        push(@{ $data->{policy} },
            {
                action => 'allow',
                value  => $secure_revision->phid,
            }
        );
    }

    my $result = request('policy.create', $data);
    return $result->{result}{phid};
}

sub make_revision_public {
    my ($revision_phid) = @_;
    return request('differential.revision.edit', {
        transactions => [
            {
                type  => 'view',
                value => 'public'
            },
            {
                type  => 'edit',
                value => 'users'
            }
        ],
        objectIdentifier => $revision_phid
    });

}

sub make_revision_private {
    my ($revision_phid) = @_;

    # When creating a private policy with no args it
    # creates one with the secure-revision project.
    my $private_policy = create_private_revision_policy();

    return request('differential.revision.edit', {
        transactions => [
            {
                type  => "view",
                value => $private_policy->phid
            },
            {
                type  => "edit",
                value => $private_policy->phid
            }
        ],
        objectIdentifier => $revision_phid
    });
}

sub edit_revision_policy {
    my ($revision_phid, $policy_phid, $subscribers) = @_;

    my $data = {
        transactions => [
            {
                type  => 'view',
                value => $policy_phid
            },
            {
                type  => 'edit',
                value => $policy_phid
            }
        ],
        objectIdentifier => $revision_phid
    };

    if (@$subscribers) {
        push(@{ $data->{transactions} }, {
            type  => 'subscribers.set',
            value => $subscribers
        });
    }

    return request('differential.revision.edit', $data);
}

sub set_revision_subscribers {
    my ($revision_phid, $subscribers) = @_;

    my $data = {
        transactions => [
            {
                type  => 'subscribers.set',
                value => $subscribers
            }
        ],
        objectIdentifier => $revision_phid
    };

    return request('differential.revision.edit', $data);
}

sub add_comment_to_revision {
    my ($revision_phid, $comment) = @_;

    my $data = {
        transactions => [
            {
                type  => 'comment',
                value => $comment
            }
        ],
        objectIdentifier => $revision_phid
    };
    return request('differential.revision.edit', $data);
}

sub get_project_phid {
    my $project = shift;
    my $memcache = Bugzilla->memcached;

    # Check memcache
    my $project_phid = $memcache->get_config({ key => "phab_project_phid_" . $project });
    if (!$project_phid) {
        my $data = {
            queryKey => 'all',
            constraints => {
                name => $project
            }
        };

        my $result = request('project.search', $data);
        return undef
            unless (exists $result->{result}{data} && @{ $result->{result}{data} });

        # If name is used as a query param, we need to loop through and look
        # for exact match as Conduit will tokenize the name instead of doing
        # exact string match :(
        foreach my $item ( @{ $result->{result}{data} } ) {
            next if $item->{fields}{name} ne $project;
            $project_phid = $item->{phid};
        }

        $memcache->set_config({ key => "phab_project_phid_" . $project, data => $project_phid });
    }
    return $project_phid;
}

sub create_project {
    my ($project, $description, $members) = @_;

    my $secure_revision = Bugzilla::Extension::PhabBugz::Project->new_from_query({
        name => 'secure-revision'
    });

    my $data = {
        transactions => [
            { type => 'name',  value => $project               },
            { type => 'description', value => $description     },
            { type => 'edit',  value => $secure_revision->phid }.
            { type => 'join',  value => $secure_revision->phid },
            { type => 'view',  value => $secure_revision->phid },
            { type => 'icon',  value => 'group'                },
            { type => 'color', value => 'red'                  }
        ]
    };

    my $result = request('project.edit', $data);
    return $result->{result}{object}{phid};
}

sub set_project_members {
    my ($project_id, $phab_user_ids) = @_;

    my $data = {
        objectIdentifier => $project_id,
        transactions => [
            { type => 'members.set',  value => $phab_user_ids }
        ]
    };

    my $result = request('project.edit', $data);
    return $result->{result}{object}{phid};
}

sub get_members_by_bmo_id {
    my $users = shift;

    my $result = get_phab_bmo_ids({ ids => [ map { $_->id } @$users ] });

    my @phab_ids;
    foreach my $user (@$result) {
        push(@phab_ids, $user->{phid})
          if ($user->{phid} && $user->{phid} =~ /^PHID-USER/);
    }

    return \@phab_ids;
}

sub get_members_by_phid {
    my $phids = shift;

    my $result = get_phab_bmo_ids({ phids => $phids });

    my @bmo_ids;
    foreach my $user (@$result) {
        push(@bmo_ids, $user->{id})
          if ($user->{phid} && $user->{phid} =~ /^PHID-USER/);
    }

    return \@bmo_ids;
}

sub get_phab_bmo_ids {
    my ($params) = @_;
    my $memcache = Bugzilla->memcached;

    # Try to find the values in memcache first
    my @results;
    if ($params->{ids}) {
        my @bmo_ids = @{ $params->{ids} };
        for (my $i = 0; $i < @bmo_ids; $i++) {
            my $phid = $memcache->get({ key => "phab_user_bmo_id_" . $bmo_ids[$i] });
            if ($phid) {
                push(@results, {
                    id   => $bmo_ids[$i],
                    phid => $phid
                });
                splice(@bmo_ids, $i, 1);
            }
        }
        $params->{ids} = \@bmo_ids;
    }

    if ($params->{phids}) {
        my @phids = @{ $params->{phids} };
        for (my $i = 0; $i < @phids; $i++) {
            my $bmo_id = $memcache->get({ key => "phab_user_phid_" . $phids[$i] });
            if ($bmo_id) {
                push(@results, {
                    id   => $bmo_id,
                    phid => $phids[$i]
                });
                splice(@phids, $i, 1);
            }
        }
        $params->{phids} = \@phids;
    }

    my $result = request('bugzilla.account.search', $params);

    # Store new values in memcache for later retrieval
    foreach my $user (@{ $result->{result} }) {
        $memcache->set({ key   => "phab_user_bmo_id_" . $user->{id},
                         value => $user->{phid} });
        $memcache->set({ key   => "phab_user_phid_" . $user->{phid},
                         value => $user->{id} });
        push(@results, $user);
    }

    return \@results;
}

sub is_attachment_phab_revision {
    my ($attachment) = @_;
    return ($attachment->contenttype eq PHAB_CONTENT_TYPE
            && $attachment->attacher->login eq PHAB_AUTOMATION_USER) ? 1 : 0;
}

sub get_attachment_revisions {
    my $bug = shift;

    my $revisions;

    my @attachments =
      grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

    if (@attachments) {
        my @revision_ids;
        foreach my $attachment (@attachments) {
            my ($revision_id) =
              ( $attachment->filename =~ PHAB_ATTACHMENT_PATTERN );
            next if !$revision_id;
            push( @revision_ids, int($revision_id) );
        }

        if (@revision_ids) {
            $revisions = get_revisions_by_ids( \@revision_ids );
        }
    }

    return @$revisions;
}

sub request {
    my ($method, $data) = @_;
    my $request_cache = Bugzilla->request_cache;
    my $params        = Bugzilla->params;

    my $ua = $request_cache->{phabricator_ua};
    unless ($ua) {
        $ua = $request_cache->{phabricator_ua} = LWP::UserAgent->new(timeout => 10);
        if ($params->{proxy_url}) {
            $ua->proxy('https', $params->{proxy_url});
        }
        $ua->default_header('Content-Type' => 'application/x-www-form-urlencoded');
    }

    my $phab_api_key = $params->{phabricator_api_key};
    ThrowUserError('invalid_phabricator_api_key') unless $phab_api_key;
    my $phab_base_uri = $params->{phabricator_base_uri};
    ThrowUserError('invalid_phabricator_uri') unless $phab_base_uri;

    my $full_uri = $phab_base_uri . '/api/' . $method;

    $data->{__conduit__} = { token => $phab_api_key };

    my $response = $ua->post($full_uri, { params => encode_json($data) });

    ThrowCodeError('phabricator_api_error', { reason => $response->message })
      if $response->is_error;

    my $result;
    my $result_ok = eval {
        my $content = $response->content;
        untaint($content);
        $result = decode_json( $content );
        1;
    };
    if (!$result_ok || $result->{error_code}) {
        ThrowCodeError('phabricator_api_error',
            { reason => 'JSON decode failure' }) if !$result_ok;
        ThrowCodeError('phabricator_api_error',
            { code   => $result->{error_code},
              reason => $result->{error_info} }) if $result->{error_code};
    }

    return $result;
}

sub get_security_sync_groups {
    my $bug = shift;

    my $phab_sync_groups = Bugzilla->params->{phabricator_sync_groups}
        || ThrowUserError('invalid_phabricator_sync_groups');
    my $sync_group_names = [ split('[,\s]+', $phab_sync_groups) ];

    my $bug_groups = $bug->groups_in;
    my $bug_group_names = [ map { $_->name } @$bug_groups ];

    my @set_groups = intersect($bug_group_names, $sync_group_names);

    return @set_groups;
}

sub set_phab_user {
    my $old_user = Bugzilla->user;
    my $user = Bugzilla::User->new( { name => PHAB_AUTOMATION_USER } );
    $user->{groups} = [ Bugzilla::Group->get_all ];
    Bugzilla->set_user($user);
    return $old_user;
}

sub add_security_sync_comments {
    my ($revisions, $bug) = @_;

    my $phab_error_message = 'Revision is being made private due to unknown Bugzilla groups.';

    foreach my $revision (@$revisions) {
        add_comment_to_revision( $revision->{phid}, $phab_error_message );
    }

    my $num_revisions = scalar @$revisions;
    my $bmo_error_message =
    ( $num_revisions > 1
    ? $num_revisions.' revisions were'
    : 'One revision was' )
    . ' made private due to unknown Bugzilla groups.';

    my $old_user = set_phab_user();

    $bug->add_comment( $bmo_error_message, { isprivate => 0 } );

    Bugzilla->set_user($old_user);
}

sub get_needs_review {
    my ($user) = @_;
    $user //= Bugzilla->user;
    return unless $user->id;

    my $ids = get_members_by_bmo_id([$user]);
    return [] unless @$ids;
    my $phid_user = $ids->[0];

    my $diffs = request(
        'differential.revision.search',
        {
            attachments => {
                reviewers => 1,
            },
            constraints => {
                reviewerPHIDs => [$phid_user],
                statuses      => [qw( needs-review )],
            },
            order       => 'newest',
        }
    );
    ThrowCodeError('phabricator_api_error', { reason => 'Malformed Response' })
        unless exists $diffs->{result}{data};

    # extract this reviewer's status from 'attachments'
    my @result;
    foreach my $diff (@{ $diffs->{result}{data} }) {
        my $attachments = delete $diff->{attachments};
        my $reviewers   = $attachments->{reviewers}{reviewers};
        my $review      = first { $_->{reviewerPHID} eq $phid_user } @$reviewers;
        $diff->{fields}{review_status} = $review->{status};
        push @result, $diff;
    }
    return \@result;
}

1;
