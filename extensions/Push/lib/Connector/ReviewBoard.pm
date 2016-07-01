# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::ReviewBoard;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Bug;
use Bugzilla::BugMail;
use Bugzilla::Component;
use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Group;
use Bugzilla::Product;
use Bugzilla::User;
use Bugzilla::Util qw( trim );

use constant RB_CONTENT_TYPE => 'text/x-review-board-request';
use constant AUTOMATION_USER => 'automation@bmo.tld';

sub options {
    return (
        {
            name     => 'product',
            label    => 'Product to create bugs in',
            type     => 'string',
            default  => 'Developer Services',
            required => 1,
            validate => sub {
                Bugzilla::Product->new({ name => $_[0] })
                    || die "Invalid Product ($_[0])\n";
            },
        },
        {
            name     => 'component',
            label    => 'Component to create bugs in',
            type     => 'string',
            default  => 'MozReview',
            required => 1,
            validate => sub {
                my ($component, $config) = @_;
                    my $product = Bugzilla::Product->new({ name => $config->{product} })
                        || die "Invalid Product (" . $config->{product} . ")\n";
                    Bugzilla::Component->new({ product => $product, name => $component })
                        || die "Invalid Component ($component)\n";
            },
        },
        {
            name     => 'version',
            label    => "The bug's version",
            type     => 'string',
            default  => 'Production',
            required => 1,
            validate => sub {
                my ($version, $config) = @_;
                    my $product = Bugzilla::Product->new({ name => $config->{product} })
                        || die "Invalid Product (" . $config->{product} . ")\n";
                    Bugzilla::Version->new({ product => $product, name => $version })
                        || die "Invalid Version ($version)\n";
            },
        },
        {
            name     => 'group',
            label    => 'Security group',
            type     => 'string',
            default  => 'mozilla-employee-confidential',
            required => 1,
            validate => sub {
                Bugzilla::Group->new({ name => $_[0] })
                    || die "Invalid Group ($_[0])\n";
            },
        },
        {
            name     => 'cc',
            label    => 'Comma separated list of users to CC',
            type     => 'string',
            default  => '',
            required => 1,
            validate => sub {
                foreach my $login (map { trim($_) } split(',', $_[0])) {
                    Bugzilla::User->new({ name => $login })
                        || die "Invalid User ($login)\n";
                }
            },
        },
    );
}

sub should_send {
    my ($self, $message) = @_;

    if ($message->routing_key =~ /^(?:attachment|bug)\.modify:.*\bis_private\b/) {
        my $payload = $message->payload_decoded();
        my $target  = $payload->{event}->{target};

        if ($target ne 'bug' && exists $payload->{$target}->{bug}) {
            return 0 if $payload->{$target}->{bug}->{is_private};
            return 0 if $payload->{$target}->{content_type} ne RB_CONTENT_TYPE;
        }

        return $payload->{$target}->{is_private} ? 1 : 0;
    }
    else {
        # We're not interested in the message.
        return 0;
    }
}

sub send {
    my ($self, $message) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    eval {
        my $payload = $message->payload_decoded();
        my $target  = $payload->{event}->{target};

        # load attachments
        my $bug_id = $target eq 'bug' ? $payload->{bug}->{id} : $payload->{attachment}->{bug}->{id};
        my $attach_id = $target eq 'attachment' ? $payload->{attachment}->{id} : undef;
        Bugzilla->set_user(Bugzilla::User->super_user);
        my $bug = Bugzilla::Bug->new({ id => $bug_id, cache => 1 });
        Bugzilla->logout;

        # create a bug if there are any mozreview attachments
        my @reviews = grep { $_->contenttype eq RB_CONTENT_TYPE } @{ $bug->attachments };
        if (@reviews) {

            # build comment
            my $comment = $target eq 'bug'
                ? "Bug $bug_id has MozReview reviews and is no longer public."
                : "MozReview attachment $attach_id on Bug $bug_id is no longer public.";
            $comment .= "\n\n";
            foreach my $attachment (@reviews) {
                $comment .= $attachment->data . "\n";
            }

            # create bug
            my $user = Bugzilla::User->new({ name => AUTOMATION_USER, cache => 1 });
            die "Invalid User: " . AUTOMATION_USER . "\n" unless $user;
            Bugzilla->set_user($user);
            my $new_bug = Bugzilla::Bug->create({
                short_desc   => "[SECURITY] Bug $bug_id is no longer public",
                product      => $config->{product},
                component    => $config->{component},
                bug_severity => 'normal',
                groups       => [ map { trim($_) } split(',', $config->{group}) ],
                op_sys       => 'Unspecified',
                rep_platform => 'Unspecified',
                version      => $config->{version},
                cc           => [ map { trim($_) } split(',', $config->{cc}) ],
                comment      => $comment,
            });
            Bugzilla::BugMail::Send($new_bug->id, { changer => Bugzilla->user });
            Bugzilla->logout;

            $logger->info("Created bug " . $new_bug->id);
        }
    };
    my $error = $@;
    Bugzilla->logout;
    if ($error) {
        return (PUSH_RESULT_TRANSIENT, clean_error($error));
    }

    return PUSH_RESULT_OK;
}

1;
