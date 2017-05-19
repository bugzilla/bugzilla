#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This script obsoletes attachments containing URLs to MozReview parent
# review requests and adds attachments, with review flags, for MozReview
# child (commit) review requests to match the new scheme.

use strict;
use warnings;
use 5.10.1;

use lib qw(. lib local/lib/perl5);

BEGIN {
    use Bugzilla;
    Bugzilla->extensions;
}
use Bugzilla::Constants qw( USAGE_MODE_CMDLINE );
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Flag;
use Bugzilla::FlagType;
use JSON;
use LWP::Simple qw( get $ua );

$Bugzilla::Flag::disable_flagmail = 1;

if (my $proxy = Bugzilla->params->{proxy_url}) {
    $ua->proxy('https', $proxy);
}

my $MOZREVIEW_MIMETYPE = 'text/x-review-board-request';

# Disable the "cannot ask for review" so we can reassign their flags to
# the new attachments.
Bugzilla->params->{max_reviewer_last_seen} = 0;

my $rb_host = shift or die "syntax: $0 review-board-url\n";
$rb_host =~ s#/$##;

sub rr_url {
    my ($rrid) = @_;
    return $rb_host . "/r/" . $rrid . "/";
}

sub set_review_flag {
    my ($child_attach, $flag_type, $flag_status, $reviewer, $setter) = @_;

    my %params = (
        type_id => $flag_type->id,
        status  => $flag_status
    );

    if ($flag_status eq "?") {
        $params{'requestee'} = $reviewer->login;
        $params{'setter'} = $setter;
    } else {
        $params{'setter'} = $reviewer;
    }

    return Bugzilla::Flag->set_flag($child_attach, \%params);
}

my $dbh = Bugzilla->dbh;

my $bugs_query = "SELECT distinct bug_id FROM attachments WHERE mimetype='text/x-review-board-request' AND isobsolete=0";
my $bug_ids = $dbh->selectcol_arrayref($bugs_query);
my $total_bugs = scalar @$bug_ids;
$total_bugs or die "No bugs were found.\n";
my $bug_count = 0;

print <<EOF;
About to convert MozReview attachments for $total_bugs bugs.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

foreach my $bug_id (@$bug_ids) {
    $dbh->bz_start_transaction();
    my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    my $bug_changed = 0;
    my $bug = Bugzilla::Bug->new($bug_id);
    print "Bug " . $bug->id . " (" . ++$bug_count  . "/" . $total_bugs . ")\n";

    my $url = $rb_host . "/api/extensions/mozreview.extension.MozReviewExtension/summary/?bug=" . $bug->id;
    print "  Fetching reviews from $url...\n";
    my $body = get($url);
    die "Error fetching review requests for bug " . $bug->id
        unless defined $body;

    my $data = from_json($body);
    my $summaries = $data->{"review_request_summaries"};
    my $attachments = Bugzilla::Attachment->get_attachments_by_bug($bug);
    my %attach_map;

    my $flag_types = Bugzilla::FlagType::match({
        'target_type'  => 'attachment',
        'product_id'   => $bug->product_id,
        'component_id' => $bug->component_id,
        'is_active'    => 1});
    my $flag_type;

    foreach my $ft (@$flag_types) {
        if ($ft->is_active && $ft->name eq "review") {
            $flag_type = $ft;
            last;
        }
    }

    if (!defined($flag_type)) {
        print "      Couldn't find flag type for attachments on this bug!\n";
        $dbh->bz_rollback_transaction();
        next;
    }

    foreach my $attachment (@$attachments) {
        next if ($attachment->isobsolete
                 || $attachment->contenttype ne $MOZREVIEW_MIMETYPE);

        print "  Attachment " . $attachment->id . ": " . $attachment->data . "\n";
        my ($rrid) = $attachment->data =~ m#/r/(\d+)/?$#;
        if (!defined($rrid)) {
            print "    Malformed or missing reviewboard URL\n";
            next;
        }

        $attach_map{$attachment->data} = $attachment;
    }

    foreach my $summary (@$summaries) {
        my $parent = $summary->{"parent"};
        my $attacher = Bugzilla::User->new({ id => $parent->{"submitter_bmo_id"},
                                             cache => 1 });
        Bugzilla->set_user($attacher);
        print "  Parent review request " . $parent->{"id"} . "\n";

        # %parent_flags is used to keep track of review flags related to
        # reviewers.  It maps requestee => status if status is "?" or
        # setter => status otherwise.
        my %parent_flags;

        my $parent_url = rr_url($parent->{"id"});
        my $parent_attach = $attach_map{$parent_url};
        if (defined($parent_attach)) {
            print "    Parent attachment has ID " . $parent_attach->id . ". Obsoleting it.\n";
            foreach my $flag (@{ $parent_attach->flags }) {
                if ($flag->type->name eq "review") {
                    if ($flag->status eq "?") {
                        $parent_flags{$flag->requestee->id} = $flag;
                    } else {
                        $parent_flags{$flag->setter->id} = $flag;
                    }
                }
            }
            $parent_attach->set_is_obsolete(1);
            $parent_attach->update($timestamp);
            print "    Posting comment.\n";
            $bug->add_comment('',
                { isprivate  => 0,
                  type       => CMT_ATTACHMENT_UPDATED,
                  extra_data => $parent_attach->id });
            $bug_changed = 1;
        } else {
            print "    Parent attachment not found.\n";
        }

        my @children = @{ $summary->{"children"} };
        foreach my $child (@children) {
            print "    Child review request " . $child->{"id"} . "\n";
            my $child_url = rr_url($child->{"id"});
            my $child_attach = $attach_map{$child_url};
            if (defined($child_attach)) {
                print "      Found attachment.\n";
                next;
            }

            print "      No attachment found for child " . $child_url . "\n";
            my %child_attach_params = (
                bug => $bug,
                data => $rb_host . "/r/" . $child->{"id"} . "/",
                description => "MozReview Request: " . $child->{"summary"},
                filename => "reviewboard-" . $child->{"id"} . "-url.txt",
                mimetype => $MOZREVIEW_MIMETYPE,
            );
            $child_attach = Bugzilla::Attachment->create(\%child_attach_params);
            print "      New attachment id: " . $child_attach->id . "\n";
            $bug_changed = 1;

            # Set flags.  If there was a parent, check it for flags by the
            # requestee.  Otherwise, set an r? flag.

            # Preserve the original flag hash since we need to modify it for
            # every child to find extra reviewers (see below the 'foreach').
            my %tmp_parent_flags = %parent_flags;

            foreach my $reviewer_id (@{ $child->{"reviewers_bmo_ids"} }) {
                my $reviewer = Bugzilla::User->new({ id => $reviewer_id,
                                                     cache => 1 });
                print "      Reviewer " . $reviewer->login . " (" . $reviewer->id . ")\n";
                $reviewer->settings->{block_reviews}->{value} = 'off';
                my $flag = $tmp_parent_flags{$reviewer->id};
                if (defined($flag)) {
                    print "      Flag for reviewer " . $reviewer->id . ": " . $flag->status . "\n";

                    set_review_flag($child_attach, $flag_type, $flag->status,
                                    $reviewer, $attacher);
                    delete $tmp_parent_flags{$reviewer->id};
                } else {
                    # No flag on the parent; this probably means the reviewer
                    # canceled the review, so don't set r?.
                    print "      No review flag for reviewer " . $reviewer->id . "\n";
                }
            }

            # Preserve flags that were set directly on the attachment
            # from reviewers not listed in the review request.
            foreach my $extra_reviewer_id (keys %tmp_parent_flags) {
                my $extra_reviewer = Bugzilla::User->new({
                    id => $extra_reviewer_id,
                    cache => 1
                });
                my $flag = $tmp_parent_flags{$extra_reviewer_id};
                print "     Extra flag set for reviewer " . $extra_reviewer->login . "\n";
                set_review_flag($child_attach, $flag->type, $flag->status,
                                $extra_reviewer, $flag->setter);
            }

            $child_attach->update($timestamp);
            print "      Posting comment.\n";
            $bug->add_comment('',
                              { isprivate  => 0,
                                type       => CMT_ATTACHMENT_CREATED,
                                extra_data => $child_attach->id });
        }
    }

    if ($bug_changed) {
        print "    Updating bug.\n";
        $bug->update($timestamp);
        $dbh->do("UPDATE bugs SET lastdiffed = ?, delta_ts = ? WHERE bug_id = ?",
                 undef, $timestamp, $timestamp, $bug_id);
    }
    $dbh->bz_commit_transaction();
    Bugzilla->memcached->clear_all();
}

print "Done.\n";
