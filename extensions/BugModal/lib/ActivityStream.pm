# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugModal::ActivityStream;
1;

package Bugzilla::Bug;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Extension::BugModal::Util qw(date_str_to_time);
use Bugzilla::User;
use Bugzilla::Constants;

# returns an arrayref containing all changes to the bug - comments, field
# changes, and duplicates
# [
#   {
#       time    => $unix_timestamp,
#       user_id => actor user-id
#       comment => optional, comment added
#       id      => unique identifier for this change-set
#       cc_only => boolean
#       activty => [
#           {
#               who     => user object
#               when    => time (string)
#               cc_only => boolean
#               changes => [
#                   {
#                       fieldname     => field name :)
#                       added         => string
#                       removed       => string
#                       flagtype_name => string (optional, name of flag if fieldname is 'flagtypes.name')
#                   }
#                   ...
#               ]
#           }
#           ...
#       ]
#   },
#   ...
# ]

sub activity_stream {
    my ($self) = @_;
    if (!$self->{activity_stream}) {
        my $stream = [];
        _add_comments_to_stream($self, $stream);
        _add_activities_to_stream($self, $stream);
        _add_duplicates_to_stream($self, $stream);

        my $base_time = date_str_to_time($self->creation_ts);
        foreach my $change_set (@$stream) {
            $change_set->{id} = $change_set->{comment}
                ? 'c' . $change_set->{comment}->count
                : 'a' . ($change_set->{time} - $base_time) . '_' . $change_set->{user_id};
            foreach my $activity (@{ $change_set->{activity} }) {
                $activity->{changes} = [
                    sort { $a->{fieldname} cmp $b->{fieldname} }
                    @{ $activity->{changes} }
                ];
            }
        }
        my $order = Bugzilla->user->setting('comment_sort_order');
        if ($order eq 'oldest_to_newest') {
            $self->{activity_stream} = [ sort { $a->{time} <=> $b->{time} } @$stream ];
        }
        elsif ($order eq 'newest_to_oldest') {
            $self->{activity_stream} = [ sort { $b->{time} <=> $a->{time} } @$stream ];
        }
        elsif ($order eq 'newest_to_oldest_desc_first') {
            my $desc = shift @$stream;
            $self->{activity_stream} = [ $desc, sort { $b->{time} <=> $a->{time} } @$stream ];
        }
    }
    return $self->{activity_stream};
}

sub find_activity_id_for_attachment {
    my ($self, $attachment) = @_;
    my $attach_id = $attachment->id;
    my $stream = $self->activity_stream;
    foreach my $change_set (@$stream) {
        next unless exists $change_set->{attach_id};
        return $change_set->{id} if $change_set->{attach_id} == $attach_id;
    }
    return undef;
}

sub find_activity_id_for_flag {
    my ($self, $flag) = @_;
    my $flagtype_name = $flag->type->name;
    my $date = $flag->modification_date;
    my $setter_id = $flag->setter->id;
    my $stream = $self->activity_stream;

    # unfortunately bugs_activity treats all flag changes as the same field, so
    # we don't have an object_id to match on

    if (!exists $self->{activity_cache}->{flag}->{$flag->id}) {
        foreach my $change_set (reverse @$stream) {
            foreach my $activity (@{ $change_set->{activity} }) {
                # match by user, timestamp, and flag-type name
                next unless
                    $activity->{who}->id == $setter_id
                    && $activity->{when} eq $date;
                foreach my $change (@{ $activity->{changes} }) {
                    next unless
                        $change->{fieldname} eq 'flagtypes.name'
                        && $change->{flagtype_name} eq $flagtype_name;
                    $self->{activity_cache}->{flag}->{$flag->id} = $change_set->{id};
                    return $change_set->{id};
                }
            }
        }
        # if we couldn't find the flag in bugs_activity it means it was set
        # during bug creation
        $self->{activity_cache}->{flag}->{$flag->id} = 'c0';
    }
    return $self->{activity_cache}->{flag}->{$flag->id};
}

# comments are processed first, so there's no need to merge into existing entries
sub _add_comment_to_stream {
    my ($stream, $time, $user_id, $comment) = @_;
    my $rh = {
        time     => $time,
        user_id  => $user_id,
        comment  => $comment,
        activity => [],
    };
    if ($comment->type == CMT_ATTACHMENT_CREATED || $comment->type == CMT_ATTACHMENT_UPDATED) {
        $rh->{attach_id} = $comment->extra_data;
    }
    push @$stream, $rh;
}

sub _add_activity_to_stream {
    my ($stream, $time, $user_id, $data) = @_;
    foreach my $entry (@$stream) {
        next unless $entry->{time} == $time && $entry->{user_id} == $user_id;
        $entry->{cc_only} = $entry->{cc_only} && $data->{cc_only};
        push @{ $entry->{activity} }, $data;
        return;
    }
    push @$stream, {
        time     => $time,
        user_id  => $user_id,
        comment  => undef,
        cc_only  => $data->{cc_only},
        activity => [ $data ],
    };
}

sub _add_comments_to_stream {
    my ($bug, $stream) = @_;
    my $user = Bugzilla->user;
    my $treeherder_id = Bugzilla->treeherder_user->id;

    my $raw_comments = $bug->comments();
    foreach my $comment (@$raw_comments) {
        next if $comment->type == CMT_HAS_DUPE;
        my $author_id = $comment->author->id;
        next if $comment->is_private && !($user->is_insider || $user->id == $author_id);
        next if $comment->body eq '' && ($comment->work_time - 0) != 0 && $user->is_timetracker;

        # treeherder is so spammy we hide its comments by default
        if ($author_id == $treeherder_id) {
            $comment->{collapsed} = 1;
            $comment->{collapsed_reason} = $comment->author->name;
        }
        if ($comment->type != CMT_ATTACHMENT_CREATED && $comment->count == 0 && length($comment->body) == 0) {
            $comment->{collapsed} = 1;
            $comment->{collapsed_reason} = 'empty';
        }
        # If comment type is resolved as duplicate, do not add '...marked as duplicate...' string to comment body
        if ($comment->type == CMT_DUPE_OF) {
            $comment->set_type(0);
            # Skip if user did not supply comment also
            next if $comment->body eq '';
        }

        _add_comment_to_stream($stream, date_str_to_time($comment->creation_ts), $comment->author->id, $comment);
    }
}

sub _add_activities_to_stream {
    my ($bug, $stream) = @_;
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    # build bug activity
    my ($raw_activity) = $bug->can('get_activity')
        ? $bug->get_activity()
        : Bugzilla::Bug::GetBugActivity($bug->id);

    # allow other extensions to alter history
    Bugzilla::Hook::process('inline_history_activitiy', { activity => $raw_activity });

    my %attachment_cache;
    foreach my $attachment (@{$bug->attachments}) {
        $attachment_cache{$attachment->id} = $attachment;
    }

    # build a list of bugs we need to check visibility of, so we can check with a single query
    my %visible_bug_ids;

    # envelope, augment and tweak
    foreach my $operation (@$raw_activity) {

        # make operation.who an object
        $operation->{who} = Bugzilla::User->new({ name => $operation->{who}, cache => 1 });

        # we need to track operations which are just cc changes
        $operation->{cc_only} = 1;

        for (my $i = 0; $i < scalar(@{$operation->{changes}}); $i++) {
            my $change = $operation->{changes}->[$i];

            # make an attachment object
            if ($change->{attachid}) {
                $change->{attach} = $attachment_cache{$change->{attachid}};
            }

            # empty resolutions are displayed as --- by default
            # make it explicit here to enable correct display of the change
            if ($change->{fieldname} eq 'resolution') {
                $change->{removed} = '---' if $change->{removed} eq '';
                $change->{added} = '---' if $change->{added} eq '';
            }

            # make boolean fields true/false instead of 1/0
            my ($table, $field) = ('bugs', $change->{fieldname});
            if ($field =~ /^([^\.]+)\.(.+)$/) {
                ($table, $field) = ($1, $2);
            }
            my $column = $dbh->bz_column_info($table, $field);
            if ($column && $column->{TYPE} eq 'BOOLEAN') {
                $change->{removed} = '';
                $change->{added} = $change->{added} ? 'true' : 'false';
            }

            # load field object (only required for custom fields), and set the
            # field type for custom fields
            my $field_obj;
            if ($change->{fieldname} =~ /^cf_/) {
                $field_obj = Bugzilla::Field->new({ name => $change->{fieldname}, cache => 1 });
                $change->{fieldtype} = $field_obj->type;
            }

            # identify buglist changes
            if ($change->{fieldname} eq 'blocked' ||
                $change->{fieldname} eq 'dependson' ||
                $change->{fieldname} eq 'dupe' ||
                ($field_obj && $field_obj->type == FIELD_TYPE_BUG_ID)
            ) {
                $change->{buglist} = 1;
                foreach my $what (qw(removed added)) {
                    my @buglist = split(/[\s,]+/, $change->{$what});
                    foreach my $id (@buglist) {
                        if ($id && $id =~ /^\d+$/) {
                            $visible_bug_ids{$id} = 1;
                        }
                    }
                }
            }

            # split see-also
            if ($change->{fieldname} eq 'see_also') {
                my $url_base = Bugzilla->localconfig->{urlbase};
                foreach my $f (qw( added removed )) {
                    my @values;
                    foreach my $value (split(/, /, $change->{$f})) {
                        my ($bug_id) = substr($value, 0, length($url_base)) eq $url_base
                            ? $value =~ /id=(\d+)$/
                            : undef;
                        push @values, {
                            url    => $value,
                            bug_id => $bug_id,
                        };
                    }
                    $change->{$f} = \@values;
                }
            }

            # track cc-only
            if ($change->{fieldname} ne 'cc') {
                $operation->{cc_only} = 0;
            }

            # split multiple flag changes (must be processed last)
            # set $change->{flagtype_name} to make searching the activity
            # stream for flag changes easier and quicker
            if ($change->{fieldname} eq 'flagtypes.name') {
                my @added = split(/, /, $change->{added});
                my @removed = split(/, /, $change->{removed});
                if (scalar(@added) <= 1 && scalar(@removed) <= 1) {
                    $change->{flagtype_name} = _extract_flagtype($added[0] || $removed[0]);
                    next;
                }
                # remove current change
                splice(@{$operation->{changes}}, $i, 1);
                # restructure into added/removed for each flag
                my %flags;
                foreach my $flag (@added) {
                    $flags{$flag}{added} = $flag;
                    $flags{$flag}{removed} = '';
                }
                foreach my $flag (@removed) {
                    $flags{$flag}{added} = '';
                    $flags{$flag}{removed} = $flag;
                }
                # clone current change, modify and insert
                foreach my $flag (sort keys %flags) {
                    my $flag_change = {};
                    foreach my $key (keys %$change) {
                        $flag_change->{$key} = $change->{$key};
                    }
                    $flag_change->{removed} = $flags{$flag}{removed};
                    $flag_change->{added} = $flags{$flag}{added};
                    $flag_change->{flagtype_name} = _extract_flagtype($flag);
                    splice(@{$operation->{changes}}, $i, 0, $flag_change);
                }
                $i--;
            }
        }

        _add_activity_to_stream($stream, date_str_to_time($operation->{when}), $operation->{who}->id, $operation);
    }

    # prime the visible-bugs cache
    $user->visible_bugs([keys %visible_bug_ids]);
}

sub _extract_flagtype {
    my ($value) = @_;
    return $value =~ /^(.+)[\?\-\+]/ ? $1 : undef;
}

# display 'duplicate of this bug' as an activity entry, not a comment
sub _add_duplicates_to_stream {
    my ($bug, $stream) = @_;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        SELECT longdescs.who,
               UNIX_TIMESTAMP(bug_when), " .
               $dbh->sql_date_format('bug_when') . ",
               type,
               extra_data
          FROM longdescs
               INNER JOIN profiles ON profiles.userid = longdescs.who
         WHERE bug_id = ? AND (type = ? OR type = ?)
         ORDER BY bug_when
    ");
    $sth->execute($bug->id, CMT_HAS_DUPE, CMT_DUPE_OF);

    while (my($who, $time, $when, $type, $dupe_id) = $sth->fetchrow_array) {
        _add_activity_to_stream($stream, $time, $who, {
            who     => Bugzilla::User->new({ id => $who, cache => 1 }),
            when    => $when,
            changes => [{
                fieldname   => ($type == CMT_HAS_DUPE ? 'has_dupe' : 'dupe_of'),
                added       => $dupe_id,
                buglist     => 1,
            }],
        });
    }
}

1;
