# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use QA::Util;
use QA::Tests qw(STANDARD_BUG_TESTS PRIVATE_BUG_USER);
use Data::Dumper;
use List::Util qw(first);
use MIME::Base64;
use Test::More tests => 313;
my ($config, @clients) = get_rpc_clients();

################
# Bug ID Tests #
################

our %attachments;

sub post_bug_success {
    my ($call, $t) = @_;

    my $bugs = $call->result->{bugs};
    is(scalar keys %$bugs, 1, "Got exactly one bug")
        or diag(Dumper($call->result));

    my $bug_attachments = (values %$bugs)[0];
    # Collect attachment ids
    foreach my $alias (qw(public_bug private_bug)) {
        foreach my $is_private (0, 1) {
            my $find_desc = "${alias}_${is_private}";
            my $attachment = first { $_->{summary} eq $find_desc }
                                   reverse @$bug_attachments;
            if ($attachment) {
                $attachments{$find_desc} = $attachment->{id};
            }
        }
    }
}

foreach my $rpc (@clients) {
    $rpc->bz_run_tests(tests => STANDARD_BUG_TESTS, method => 'Bug.attachments',
                       post_success => \&post_bug_success);
}

foreach my $alias (qw(public_bug private_bug)) {
    foreach my $is_private (0, 1) {
        ok($attachments{"${alias}_${is_private}"},
           "Found attachment id for ${alias}_${is_private}");
    }
}

####################
# Attachment Tests #
####################

my $content_file = '../config/generate_test_data.pl';
open(my $fh, '<', $content_file) or die "$content_file: $!";
my $content;
{ local $/; $content = <$fh>; }
close($fh);

# Access tests for public/private stuff, and also validate that the
# format of each return value is correct.

my @tests = (
    # Logged-out user
    { args => { attachment_ids => [$attachments{'public_bug_0'}] },
      test => 'Logged-out user can access public attachment on public'
              . '  bug by id',
    },
    { args  => { attachment_ids => [$attachments{'public_bug_1'}] },
      test  => 'Logged-out user cannot access private attachment on public bug',
      error => 'Sorry, you are not authorized',
    },
    { args  => { attachment_ids => [$attachments{'private_bug_0'}] },
      test  => 'Logged-out user cannot access attachments by id on private bug',
      error => 'You are not authorized to access',
    },
    { args  => { attachment_ids => [$attachments{'private_bug_1'}] },
      test  => 'Logged-out user cannot access private attachment on '
               . ' private bug',
      error => 'You are not authorized to access',
    },

    # Logged-in, unprivileged user.
    { user => 'unprivileged',
      args => { attachment_ids => [$attachments{'public_bug_0'}] },
      test => 'Logged-in user can see a public attachment on a public bug by id',
    },
    { user  => 'unprivileged',
      args  => { attachment_ids => [$attachments{'public_bug_1'}] },
      test  => 'Logged-in user cannot access private attachment on public bug',
      error => 'Sorry, you are not authorized',
    },
    { user  => 'unprivileged',
      args  => { attachment_ids => [$attachments{'private_bug_0'}] },
      test  => 'Logged-in user cannot access attachments by id on private bug',
      error => "You are not authorized to access",
    },
    { user  => 'unprivileged',
      args  => { attachment_ids => [$attachments{'private_bug_1'}] },
      test  => 'Logged-in user cannot access private attachment on private bug',
      error => "You are not authorized to access",
    },

    # User who can see private bugs and private attachments
    { user => PRIVATE_BUG_USER,
      args => { attachment_ids => [$attachments{'public_bug_1'}] },
      test => PRIVATE_BUG_USER . ' can see private attachment on public bug',
    },
    { user  => PRIVATE_BUG_USER,
      args  => { attachment_ids => [$attachments{'private_bug_1'}] },
      test  => PRIVATE_BUG_USER . ' can see private attachment on private bug',
    },
);

sub post_success {
    my ($call, $t, $rpc) = @_;
    is(scalar keys %{ $call->result->{attachments} }, 1,
       "Got exactly one attachment");
    my $attachment = (values %{ $call->result->{attachments} })[0];

    cmp_ok($attachment->{last_change_time}, '=~', $rpc->DATETIME_REGEX,
           "last_change_time is in the right format");
    cmp_ok($attachment->{creation_time}, '=~', $rpc->DATETIME_REGEX,
           "creation_time is in the right format");
    is($attachment->{is_obsolete}, 0, 'is_obsolete is 0');
    cmp_ok($attachment->{bug_id}, '=~', qr/^\d+$/, "bug_id is an integer");
    cmp_ok($attachment->{id}, '=~', qr/^\d+$/, "id is an integer");
    is($attachment->{content_type}, 'application/x-perl',
       "content_type is correct");
    cmp_ok($attachment->{file_name}, '=~', qr/^\w+\.pl$/,
           "filename is in the expected format");
    is($attachment->{creator}, $config->{QA_Selenium_TEST_user_login},
       "creator is the correct user");
    my $data = $attachment->{data};
    $data = decode_base64($data) if $rpc->isa('QA::RPC::JSONRPC');
    is($data, $content, 'data is correct');
    is($attachment->{size}, length($data), "size matches data's size");
}

foreach my $rpc (@clients) {
    $rpc->bz_run_tests(method => 'Bug.attachments', tests => \@tests,
                       post_success => \&post_success);
}
