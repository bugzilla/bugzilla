# This Source Code Form is subject to the terms of the Mozilla Public
# # License, v. 2.0. If a copy of the MPL was not distributed with this
# # file, You can obtain one at http://mozilla.org/MPL/2.0/.
# #
# # This Source Code Form is "Incompatible With Secondary Licenses", as
# # defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::Phabricator;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::User;

use constant PHAB_CONTENT_TYPE => 'text/x-phabricator-request';

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

    if (!(  $message->routing_key
            =~ /^(?:attachment|bug)\.modify:.*\bbug_group\b/
        )
        )
    {
        return 0;
    }

    my $data = $message->payload_decoded;
    my $bug_data = $self->_get_bug_data($data) || return 0;
    my $bug = Bugzilla::Bug->new( { id => $bug_data->{id}, cache => 1 } );
    my $has_phab_stub_attachment
        = $bug->has_attachment_with_mimetype(PHAB_CONTENT_TYPE);

    if ($has_phab_stub_attachment) {
        return 1;
    }

    return 0;
}

sub send {
    my $logger = Bugzilla->push_ext->logger;

    $logger->info('AUDIT');

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
