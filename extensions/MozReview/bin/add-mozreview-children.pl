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

use FindBin qw($RealBin);
use lib "$RealBin/../../..";

BEGIN {
    use Bugzilla;
    Bugzilla->extensions;
}
use Bugzilla::Constants qw( USAGE_MODE_CMDLINE );
Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

use Bugzilla::Attachment;
use Bugzilla::Bug;
use Bugzilla::Constants;
use JSON;
use LWP::Simple qw( get $ua );

if (my $proxy = Bugzilla->params->{proxy_url}) {
    $ua->proxy('https', $proxy);
}

# Disable the "cannot ask for review" so we can reassign their flags to
# the new attachments.
Bugzilla->params->{max_reviewer_last_seen} = 0;

my $rb_host = shift or die "syntax: $0 review-board-url\n";
$rb_host =~ s#/$##;

my $dbh = Bugzilla->dbh;

$dbh->bz_start_transaction();

my $bugs_query = "SELECT distinct bug_id FROM attachments WHERE mimetype='text/x-review-board-request' AND isobsolete=0";
my $bug_ids = $dbh->selectcol_arrayref($bugs_query);
my $bug_count = scalar @$bug_ids;
$bug_count or die "No bugs were found.\n";

print <<EOF;
About to convert MozReview attachments for $bug_count bugs.

Press <Ctrl-C> to stop or <Enter> to continue...
EOF
getc();

foreach my $bug_id (@$bug_ids) {
    my $timestamp = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    my $bug = Bugzilla::Bug->new($bug_id);
    print "Bug " . $bug->id . "\n";

    my $url = $rb_host . "/api/extensions/mozreview.extension.MozReviewExtension/summary/?bug=" . $bug->id;
    print "  Fetching reviews from $url...\n";
    my $body = get($url);
    die "Error fetching review requests for bug " . $bug->id
        unless defined $body;

    my $attachments = Bugzilla::Attachment->get_attachments_by_bug($bug);
    my %families;
    my $data = from_json($body);
    my $summaries = $data->{"review_request_summaries"};
    foreach my $summary (@$summaries) {
        $families{$summary->{"parent"}->{"id"}} = $summary;
    }
    foreach my $attachment (@$attachments) {
        next if ($attachment->isobsolete
                 || $attachment->contenttype ne 'text/x-review-board-request');
        print "  Attachment " . $attachment->id . ": " . $attachment->data . "\n";
        my ($rrid) = $attachment->data =~ m#/r/(\d+)/?$#;
        if (!defined($rrid)) {
            print "    Malformed or missing reviewboard URL\n";
            next;
        }
        my $family = $families{$rrid};
        if (!defined($family)) {
            print "    Cannot find family with parent $rrid associated with bug " . $bug->id . "\n";
            next;
        }
        my @children = @{ $family->{"children"} };
        print "  Commit requests:\n";
        foreach my $child (@children) {
            print "    Review request " . $child->{"id"} . ": " . $child->{"summary"} . "\n";
            Bugzilla->set_user($attachment->attacher);
            my %child_attach_params = (
                bug => $bug,
                data => $rb_host . "/r/" . $child->{"id"} . "/",
                description => "MozReview Request: " . $child->{"summary"},
                filename => "reviewboard-" . $child->{"id"} . "-url.txt",
                mimetype => $attachment->contenttype,
            );
            my $flag_type;
            foreach my $ft (@{ $attachment->flag_types }) {
                if ($ft->is_active && $ft->name eq "review") {
                    $flag_type = $ft;
                    last;
                }
            }
            my $child_attach = Bugzilla::Attachment->create(\%child_attach_params);
            print "      New attachment id: " . $child_attach->id . "\n";
            foreach my $reviewer_id (@{ $child->{"reviewers_bmo_ids"} }) {
                my $reviewer = Bugzilla::User->new({ id => $reviewer_id,
                                                     cache => 1 });
                print "      Adding reviewer " . $reviewer->login . "\n";
                my $child_flag = Bugzilla::Flag->set_flag($child_attach, {
                    type_id => $flag_type->id,
                    status => "?",
                    requestee => $reviewer->login,
                    setter => $attachment->attacher,
                });
            }
            $child_attach->update($timestamp);

            print "      Posting comment.\n";
            $bug->add_comment('',
                { isprivate  => 0,
                  type       => CMT_ATTACHMENT_CREATED,
                  extra_data => $child_attach->id });
        }
        print "    Obsoleting parent attachment.\n";
        $attachment->set_is_obsolete(1);
        $attachment->update($timestamp);
        print "    Posting comment.\n";
        $bug->add_comment('',
            { isprivate  => 0,
              type       => CMT_ATTACHMENT_UPDATED,
              extra_data => $attachment->id });
    }
    print "    Updating bug.\n";
    $bug->update($timestamp);
    $dbh->do("UPDATE bugs SET lastdiffed = ?, delta_ts = ? WHERE bug_id = ?",
             undef, $timestamp, $timestamp, $bug_id);
}

$dbh->bz_commit_transaction();

Bugzilla->memcached->clear_all();

print "Done.\n";
