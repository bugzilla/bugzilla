# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozReview;

use 5.10.1;
use strict;
use warnings;
use parent qw(Bugzilla::Extension);

use Bugzilla::Attachment;
use Bugzilla::Config::Common;

our $VERSION = '0.01';

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};

    return unless (($file eq 'bug/show-header.html.tmpl' ||
                    $file eq 'bug_modal/header.html.tmpl' ||
                    $file eq 'attachment/create.html.tmpl') &&
                   Bugzilla->params->{mozreview_base_url});

    my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'};

    if ($bug) {
        if ($file eq 'attachment/create.html.tmpl') {
            if ($bug->product eq 'Core' || $bug->product eq 'Firefox' ||
                $bug->product eq 'Firefox for Android') {
                $vars->{'mozreview_enabled'} = 1;
            }
        } else {
            my @rrids;
            my $attachments = Bugzilla::Attachment->get_attachments_by_bug($bug);

            foreach my $attachment (@$attachments) {
                if ($attachment->contenttype eq 'text/x-review-board-request'
                    && !$attachment->isobsolete) {
                    push @rrids, ($attachment->data =~ m#/r/(\d+)/?$#);
                }
            }

            if (scalar @rrids) {
                $vars->{'mozreview'} = 1;
                $vars->{'review_request_ids'} = \@rrids;
            }
        }
    }
}

sub config_modify_panels {
    my ($self, $args) = @_;
    push @{ $args->{panels}->{advanced}->{params} }, {
        name    => 'mozreview_base_url',
        type    => 't',
        default => '',
        checker => \&check_urlbase
    };
}

__PACKAGE__->NAME;
