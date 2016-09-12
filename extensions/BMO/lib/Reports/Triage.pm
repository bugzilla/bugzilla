# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::Triage;
use strict;

use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::Util qw(detaint_natural);
use Date::Parse;

# set an upper limit on the *unfiltered* number of bugs to process
use constant MAX_NUMBER_BUGS => 4000;

sub report {
    my ($vars, $filter) = @_;
    my $dbh = Bugzilla->dbh;
    my $input = Bugzilla->input_params;
    my $user = Bugzilla->user;

    if (exists $input->{'action'} && $input->{'action'} eq 'run' && $input->{'product'}) {

        # load product and components from input

        my $product = Bugzilla::Product->new({ name => $input->{'product'} })
            || ThrowUserError('invalid_object', { object => 'Product', value => $input->{'product'} });

        my @component_ids;
        if ($input->{'component'} ne '') {
            my $ra_components = ref($input->{'component'})
                ? $input->{'component'} : [ $input->{'component'} ];
            foreach my $component_name (@$ra_components) {
                my $component = Bugzilla::Component->new({ name => $component_name, product => $product })
                    || ThrowUserError('invalid_object', { object => 'Component', value => $component_name });
                push @component_ids, $component->id;
            }
        }

        # determine which comment filters to run

        my $filter_commenter = $input->{'filter_commenter'};
        my $filter_commenter_on = $input->{'commenter'};
        my $filter_last = $input->{'filter_last'};
        my $filter_last_period = $input->{'last'};

        if (!$filter_commenter || $filter_last) {
            $filter_commenter = '1';
            $filter_commenter_on = 'reporter';
        }

        my $filter_commenter_id;
        if ($filter_commenter && $filter_commenter_on eq 'is') {
            Bugzilla::User::match_field({ 'commenter_is' => {'type' => 'single'} });
            my $user = Bugzilla::User->new({ name => $input->{'commenter_is'} })
                || ThrowUserError('invalid_object', { object => 'User', value => $input->{'commenter_is'} });
            $filter_commenter_id = $user ? $user->id : 0;
        }

        my $filter_last_time;
        if ($filter_last) {
            if ($filter_last_period eq 'is') {
                $filter_last_period = -1;
                $filter_last_time = str2time($input->{'last_is'} . " 00:00:00") || 0;
            } else {
                detaint_natural($filter_last_period);
                    $filter_last_period = 14 if $filter_last_period < 14;
            }
        }

        # form sql queries

        my $now = (time);
        my $bugs_sql = "
              SELECT bug_id, short_desc, reporter, creation_ts
                FROM bugs
               WHERE product_id = ?
                     AND bug_status = 'UNCONFIRMED'";
        if (@component_ids) {
            $bugs_sql .= " AND component_id IN (" . join(',', @component_ids) . ")";
        }
        $bugs_sql .= "
            ORDER BY creation_ts
        ";

        my $comment_count_sql = "
            SELECT COUNT(*)
              FROM longdescs
             WHERE bug_id = ?
        ";

        my $comment_sql = "
              SELECT who, bug_when, type, thetext, extra_data
                FROM longdescs
               WHERE bug_id = ?
        ";
        if (!Bugzilla->user->is_insider) {
            $comment_sql .= " AND isprivate = 0 ";
        }
        $comment_sql .= "
            ORDER BY bug_when DESC
               LIMIT 1
        ";

        my $attach_sql = "
            SELECT description, isprivate
              FROM attachments
             WHERE attach_id = ?
        ";

        # work on an initial list of bugs

        my $list = $dbh->selectall_arrayref($bugs_sql, undef, $product->id);
        my @bugs;

        # this can be slow to process, resulting in 'service unavailable' errors from zeus
        # so if too many bugs are returned, throw an error

        if (scalar(@$list) > MAX_NUMBER_BUGS) {
            ThrowUserError('report_too_many_bugs');
        }

        foreach my $entry (@$list) {
            my ($bug_id, $summary, $reporter_id, $creation_ts) = @$entry;

            next unless $user->can_see_bug($bug_id);

            # get last comment information

            my ($comment_count) = $dbh->selectrow_array($comment_count_sql, undef, $bug_id);
            my ($commenter_id, $comment_ts, $type, $comment, $extra)
                = $dbh->selectrow_array($comment_sql, undef, $bug_id);
            my $commenter = 0;

            # apply selected filters

            if ($filter_commenter) {
                next if $comment_count <= 1;

                if ($filter_commenter_on eq 'reporter') {
                    next if $commenter_id != $reporter_id;

                } elsif ($filter_commenter_on eq 'noconfirm') {
                    $commenter = Bugzilla::User->new({ id => $commenter_id, cache => 1 });
                    next if $commenter_id != $reporter_id
                        || $commenter->in_group('canconfirm');

                } elsif ($filter_commenter_on eq 'is') {
                    next if $commenter_id != $filter_commenter_id;
                }
            } else {
                $input->{'commenter'} = '';
                $input->{'commenter_is'} = '';
            }

            if ($filter_last) {
                my $comment_time = str2time($comment_ts)
                    or next;
                if ($filter_last_period == -1) {
                    next if $comment_time >= $filter_last_time;
                } else {
                    next if $now - $comment_time <= 60 * 60 * 24 * $filter_last_period;
                }
            } else {
                $input->{'last'} = '';
                $input->{'last_is'} = '';
            }

            # get data for attachment comments

            if ($comment eq '' && $type == CMT_ATTACHMENT_CREATED) {
                my ($description, $is_private) = $dbh->selectrow_array($attach_sql, undef, $extra);
                next if $is_private && !Bugzilla->user->is_insider;
                $comment = "(Attachment) " . $description;
            }

            # truncate long comments

            if (length($comment) > 80) {
                $comment = substr($comment, 0, 80) . '...';
            }

            # build bug hash for template

            my $bug = {};
            $bug->{id}            = $bug_id;
            $bug->{summary}       = $summary;
            $bug->{reporter}      = Bugzilla::User->new({ id => $reporter_id, cache => 1 });
            $bug->{creation_ts}   = $creation_ts;
            $bug->{commenter}     = $commenter || Bugzilla::User->new({ id => $commenter_id, cache => 1 });
            $bug->{comment_ts}    = $comment_ts;
            $bug->{comment}       = $comment;
            $bug->{comment_count} = $comment_count;
            push @bugs, $bug;
        }

        @bugs = sort { $b->{comment_ts} cmp $a->{comment_ts} } @bugs;

        $vars->{bugs} = \@bugs;
    } else {
        $input->{action} = '';
    }

    if (!$input->{filter_commenter} && !$input->{filter_last}) {
        $input->{filter_commenter} = 1;
    }

    $vars->{'input'} = $input;
}

1;
