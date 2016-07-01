# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozReview::WebService;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::Comment;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::WebService::Constants;
use Bugzilla::WebService::Util qw(extract_flags validate translate);
use Bugzilla::Util qw(trim);

use List::MoreUtils qw(uniq all);
use List::Util qw(max);
use Storable qw(dclone);

use constant PUBLIC_METHODS => qw( attachments );

BEGIN {
    *_attachment_to_hash = \&Bugzilla::WebService::Bug::_attachment_to_hash;
    *_flag_to_hash = \&Bugzilla::WebService::Bug::_flag_to_hash;
}

sub attachments {
    my ($self, $params) = validate(@_, 'attachments');
    my $dbh = Bugzilla->dbh;

    # BMO: Don't allow updating of bugs if disabled
    if (Bugzilla->params->{disable_bug_updates}) {
        ThrowErrorPage('bug/process/updates-disabled.html.tmpl',
            'Bug updates are currently disabled.');
    }

    my $user = Bugzilla->login(LOGIN_REQUIRED);

    ThrowCodeError('param_required', { param => 'attachments' })
      unless defined $params->{attachments};

    my $bug = Bugzilla::Bug->check($params->{bug_id});

    ThrowUserError("product_edit_denied", { product => $bug->product })
      unless $user->can_edit_product($bug->product_id);

    my (@modified, @created);
    $dbh->bz_start_transaction();
    my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');

    my $comment_tags = $params->{comment_tags};
    my $attachments  = $params->{attachments};

    if ($comment_tags) {
        ThrowUserError('comment_tag_disabled')
          unless Bugzilla->params->{comment_taggers_group};

        my $all_mozreview_tags = all { /^mozreview-?/i } @$comment_tags;
        if ($all_mozreview_tags || $user->can_tag_comments) {
            # there should be a method of User that does this.
            local $user->{can_tag_comments} = 1;
            $bug->set_all({ comment_tags => $comment_tags });
        }
        else {
            ThrowUserError('auth_failure',
                           { group  => Bugzilla->params->{comment_taggers_group},
                             action => 'update',
                             object => 'comment_tags' })
        }
    }

    foreach my $attachment (@$attachments) {
        my $flags         = delete $attachment->{flags};
        my $attachment_id = delete $attachment->{attachment_id};
        my $comment       = delete $attachment->{comment};
        my $attachment_obj;

        if ($attachment_id) {
            $attachment_obj = Bugzilla::Attachment->check({ id => $attachment_id });
            ThrowUserError("mozreview_attachment_bug_mismatch", { bug => $bug, attachment => $attachment_obj })
              if $attachment_obj->bug_id != $bug->id;

            # HACK: preload same bug object.
            $attachment_obj->{bug} = $bug;

            $attachment = translate($attachment, Bugzilla::WebService::Bug::ATTACHMENT_MAPPED_SETTERS);

            my ($update_flags, $new_flags) = $flags
              ? extract_flags($flags, $bug, $attachment_obj)
              : ([], []);
            if ($attachment_obj->validate_can_edit) {
                $attachment_obj->set_all($attachment);
                $attachment_obj->set_flags($update_flags, $new_flags) if $flags;
            }
            elsif (scalar @$update_flags && !scalar(@$new_flags) && !scalar keys %$attachment) {
                # Requestees can set flags targetted to them, even if they cannot
                # edit the attachment. Flag setters can edit their own flags too.
                my %flag_list = map { $_->{id} => $_ } @$update_flags;
                my $flag_objs = Bugzilla::Flag->new_from_list([ keys %flag_list ]);
                my @editable_flags;
                foreach my $flag_obj (@$flag_objs) {
                    if ($flag_obj->setter_id == $user->id
                          || ($flag_obj->requestee_id && $flag_obj->requestee_id == $user->id))
                      {
                          push(@editable_flags, $flag_list{$flag_obj->id});
                      }
                }
                if (!scalar @editable_flags) {
                    ThrowUserError('illegal_attachment_edit', { attach_id => $attachment_obj->id });
                }
                $attachment_obj->set_flags(\@editable_flags, []);
            }
            else {
                ThrowUserError('illegal_attachment_edit', { attach_id => $attachment_obj->id });
            }

            my $changes = $attachment_obj->update($timestamp);

            if (my $comment_text = trim($comment)) {
                $attachment_obj->bug->add_comment($comment_text,
                                              { isprivate  => $attachment_obj->isprivate,
                                                type       => CMT_ATTACHMENT_UPDATED,
                                                extra_data => $attachment_obj->id });
            }

            $changes = translate($changes, Bugzilla::WebService::Bug::ATTACHMENT_MAPPED_RETURNS);

            my %hash = (
                id               => $self->type('int', $attachment_obj->id),
                last_change_time => $self->type('dateTime', $attachment_obj->modification_time),
                changes          => {},
            );

            foreach my $field (keys %$changes) {
                my $change = $changes->{$field};

                # We normalize undef to an empty string, so that the API
                # stays consistent for things like Deadline that can become
                # empty.
                $hash{changes}->{$field} = {
                    removed => $self->type('string', $change->[0] // ''),
                    added   => $self->type('string', $change->[1] // '')
                };
            }

            push(@modified, \%hash);
        }
        else {
            $attachment_obj = Bugzilla::Attachment->create({
                bug         => $bug,
                creation_ts => $timestamp,
                data        => $attachment->{data},
                description => $attachment->{summary},
                filename    => $attachment->{file_name},
                mimetype    => $attachment->{content_type},
                ispatch     => $attachment->{is_patch},
                isprivate   => $attachment->{is_private},
            });

            if ($flags) {
                my ($old_flags, $new_flags) = extract_flags($flags, $bug, $attachment_obj);
                $attachment_obj->set_flags($old_flags, $new_flags);
            }

            push(@created, $attachment_obj);

            $attachment_obj->update($timestamp);
            $bug->add_comment($comment,
                              { isprivate  => $attachment_obj->isprivate,
                                type       => CMT_ATTACHMENT_CREATED,
                                extra_data => $attachment_obj->id });

        }
    }

    $bug->update($timestamp);

    $dbh->bz_commit_transaction();
    $bug->send_changes();

    my %attachments_created = map { $_->id => $self->_attachment_to_hash($_, $params) } @created;
    my %attachments_modified = map { (ref $_->{id} ? $_->{id}->value : $_->{id}) => $_ } @modified;

    return { attachments_created => \%attachments_created, attachments_modified => \%attachments_modified };
}

sub rest_resources {
    return [
        qr{^/mozreview/(\d+)/attachments$}, {
            POST => {
                method => 'attachments',
                params => sub {
                    return { bug_id => $1 };
                },
            },
        },
    ];
}

1;
