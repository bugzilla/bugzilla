# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::Phabricator;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Extension::PhabBugz::Util qw(intersect make_revision_public get_revisions_by_ids);
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::User;
use List::Util qw(any);

use constant PHAB_CONTENT_TYPE => 'text/x-phabricator-request';
use constant PHAB_ATTACHMENT_PATTERN => qr/^phabricator-D(\d+)/;

sub options {
    return (
        {   name     => 'phabricator_url',
            label    => 'Phabricator URL',
            type     => 'string',
            default  => '',
            required => 1,
        }
    );
}

sub should_send {
    my ( $self, $message ) = @_;

    return 0 unless Bugzilla->params->{phabricator_enabled};

    return 0 unless $message->routing_key =~ /^(?:attachment|bug)\.modify:.*\bbug_group\b/;

    my $data = $message->payload_decoded;
    my $bug_data = $self->_get_bug_data($data) || return 0;
    my $bug = Bugzilla::Bug->new( { id => $bug_data->{id}, cache => 1 } );

    return $bug->has_attachment_with_mimetype(PHAB_CONTENT_TYPE);
}

sub send {
    my ( $self, $message ) = @_;

    my $logger = Bugzilla->push_ext->logger;

    my $data = $message->payload_decoded;
    my $bug_data = $self->_get_bug_data($data) || return 0;
    my $bug = Bugzilla::Bug->new( { id => $bug_data->{id}, cache => 1 } );

    if(!is_public($bug)) {
        $logger->info('Bailing on send because the bug is not public');
        return PUSH_RESULT_OK;
    }

    my @attachments = grep {
        $_->isobsolete == 0 &&
        $_->contenttype eq PHAB_CONTENT_TYPE &&
        $_->attacher->login eq 'phab-bot@bmo.tld'
    } @{ $bug->attachments() };

    if(@attachments){
        my @rev_ids;
        foreach my $attachment (@attachments) {
            my ($rev_id) = ($attachment->filename =~ PHAB_ATTACHMENT_PATTERN);
            next if !$rev_id;
            push(@rev_ids, int($rev_id));
        }

        if(@rev_ids) {
            $logger->info('Getting info for revisions: ');
            $logger->info(@rev_ids);

            my @rev_details = get_revisions_by_ids(\@rev_ids);
            foreach my $rev_detail (@rev_details) {
                my $rev_phid = $rev_detail->{phid};
                $logger->info('Making revision $rev_phid public:');
                $logger->info($rev_phid);
                make_revision_public($rev_phid);
            }
        }
    }

    return PUSH_RESULT_OK;
}

sub _get_bug_data {
    my ( $self, $data ) = @_;
    my $target = $data->{event}->{target};
    if ( $target eq 'bug' ) {
        return $data->{bug};
    }
    elsif ( exists $data->{$target}->{bug} ) {
        return $data->{$target}->{bug};
    }
    else {
        return;
    }
}

1;
