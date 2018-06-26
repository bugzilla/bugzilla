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
use Try::Tiny;

use base qw(Exporter);

our @EXPORT = qw(
    add_security_sync_comments
    create_revision_attachment
    get_attachment_revisions
    get_bug_role_phids
    get_needs_review
    get_security_sync_groups
    intersect
    is_attachment_phab_revision
    request
    set_phab_user
);

sub create_revision_attachment {
    my ( $bug, $revision, $timestamp, $submitter ) = @_;

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

    # If submitter, then switch to that user when creating attachment
    my ($old_user, $attachment);
    try {
        if ($submitter) {
            $old_user = Bugzilla->user;
            $submitter->{groups} = [ Bugzilla::Group->get_all ]; # We need to always be able to add attachment
            Bugzilla->set_user($submitter);
        }

        $attachment = Bugzilla::Attachment->create(
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
    }
    catch {
        die $_;
    }
    finally {
        Bugzilla->set_user($old_user) if $old_user;
    };

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

    my $phab_users =
      Bugzilla::Extension::PhabBugz::User->match(
        {
          ids => [ map { $_->id } @bug_users ]
        }
    );

    return [ map { $_->phid } @{ $phab_users } ];
}

sub is_attachment_phab_revision {
    my ($attachment) = @_;
    return $attachment->contenttype eq PHAB_CONTENT_TYPE;
}

sub get_attachment_revisions {
    my $bug = shift;

    my @attachments =
      grep { is_attachment_phab_revision($_) } @{ $bug->attachments() };

    return unless @attachments;

    my @revision_ids;
    foreach my $attachment (@attachments) {
        my ($revision_id) =
          ( $attachment->filename =~ PHAB_ATTACHMENT_PATTERN );
        next if !$revision_id;
        push( @revision_ids, int($revision_id) );
    }

    return unless @revision_ids;

    my @revisions;
    foreach my $revision_id (@revision_ids) {
        push @revisions, Bugzilla::Extension::PhabBugz::Revision->new_from_query({
            ids => [ $revision_id ]
        });
    }

    return \@revisions;
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

    my $sync_groups = Bugzilla::Group->match( { isactive => 1, isbuggroup => 1 } );
    my $sync_group_names = [ map { $_->name } @$sync_groups ]; 

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
        $revision->add_comment($phab_error_message);
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

    my $phab_user = Bugzilla::Extension::PhabBugz::User->new_from_query(
      {
        ids => [ $user->id ]
      }
    );

    return [] unless $phab_user;

    my $diffs = request(
        'differential.revision.search',
        {
            attachments => {
                reviewers => 1,
            },
            constraints => {
                reviewerPHIDs => [$phab_user->phid],
                statuses      => [qw( needs-review )],
            },
            order       => 'newest',
        }
    );
    ThrowCodeError('phabricator_api_error', { reason => 'Malformed Response' })
        unless exists $diffs->{result}{data};

    return $diffs->{result}{data};
}

1;
