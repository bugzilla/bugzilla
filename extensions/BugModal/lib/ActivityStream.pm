# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugModal::ActivityStream;
1;

package Bugzilla::Bug;
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
#       activty => [
#           {
#               who     => user object
#               when    => time (string)
#               changes => [
#                   {
#                       fieldname   => field name :)
#                       added       => string
#                       removed     => string
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
                : 'a' . ($change_set->{time} - $base_time) . '.' . $change_set->{user_id};
            $change_set->{activity} = [
                sort { $a->{fieldname} cmp $b->{fieldname} }
                @{ $change_set->{activity} }
            ];
        }
        $self->{activity_stream} = [ sort { $a->{time} <=> $b->{time} } @$stream ];
    }
    return $self->{activity_stream};
}

# comments are processed first, so there's no need to merge into existing entries
sub _add_comment_to_stream {
    my ($stream, $time, $user_id, $comment) = @_;
    push @$stream, {
        time     => $time,
        user_id  => $user_id,
        comment  => $comment,
        activity => [],
    };
}

sub _add_activity_to_stream {
    my ($stream, $time, $user_id, $data) = @_;
    foreach my $entry (@$stream) {
        next unless $entry->{time} == $time && $entry->{user_id} == $user_id;
        push @{ $entry->{activity} }, $data;
        return;
    }
    push @$stream, {
        time     => $time,
        user_id  => $user_id,
        comment  => undef,
        activity => [ $data ],
    };
}

sub _add_comments_to_stream {
    my ($bug, $stream) = @_;
    my $user = Bugzilla->user;

    my $raw_comments = $bug->comments();
    foreach my $comment (@$raw_comments) {
        next if $comment->type == CMT_HAS_DUPE;
        next if $comment->is_private && !($user->is_insider || $user->id == $comment->author->id);
        next if $comment->body eq '' && ($comment->work_time - 0) != 0 && !$user->is_timetracker;
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
        # until we can toggle their visibility, skip CC changes
        $operation->{changes} = [ grep { $_->{fieldname} ne 'cc' } @{ $operation->{changes} } ];
        next unless @{ $operation->{changes} };

        # make operation.who an object
        $operation->{who} = Bugzilla::User->new({ name => $operation->{who}, cache => 1 });

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
                my $url_base = correct_urlbase();
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

            # split multiple flag changes (must be processed last)
            if ($change->{fieldname} eq 'flagtypes.name') {
                my @added = split(/, /, $change->{added});
                my @removed = split(/, /, $change->{removed});
                next if scalar(@added) <= 1 && scalar(@removed) <= 1;
                # remove current change
                splice(@{$operation->{changes}}, $i, 1);
                # restructure into added/removed for each flag
                my %flags;
                foreach my $added (@added) {
                    my ($value, $name) = $added =~ /^((.+).)$/;
                    $flags{$name}{added} = $value;
                    $flags{$name}{removed} |= '';
                }
                foreach my $removed (@removed) {
                    my ($value, $name) = $removed =~ /^((.+).)$/;
                    $flags{$name}{added} |= '';
                    $flags{$name}{removed} = $value;
                }
                # clone current change, modify and insert
                foreach my $flag (sort keys %flags) {
                    my $flag_change = {};
                    foreach my $key (keys %$change) {
                        $flag_change->{$key} = $change->{$key};
                    }
                    $flag_change->{removed} = $flags{$flag}{removed};
                    $flag_change->{added} = $flags{$flag}{added};
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

# display 'duplicate of this bug' as an activity entry, not a comment
sub _add_duplicates_to_stream {
    my ($bug, $stream) = @_;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        SELECT longdescs.who,
               UNIX_TIMESTAMP(bug_when), " .
               $dbh->sql_date_format('bug_when') . ",
               extra_data
          FROM longdescs
               INNER JOIN profiles ON profiles.userid = longdescs.who
         WHERE bug_id = ? AND type = ?
         ORDER BY bug_when
    ");
    $sth->execute($bug->id, CMT_HAS_DUPE);

    while (my($who, $time, $when, $dupe_id) = $sth->fetchrow_array) {
        _add_activity_to_stream($stream, $time, $who, {
            who     => Bugzilla::User->new({ id => $who, cache => 1 }),
            when    => $when,
            changes => [{
                fieldname   => 'duplicate',
                added       => $dupe_id,
                buglist     => 1,
            }],
        });
    }
}

1;
