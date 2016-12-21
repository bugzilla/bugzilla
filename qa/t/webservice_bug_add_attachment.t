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
use MIME::Base64 qw(encode_base64 decode_base64);
use Test::More tests => 187;
my ($config, $xmlrpc, $jsonrpc, $jsonrpc_get) = get_rpc_clients();

use constant INVALID_BUG_ID => -1;
use constant INVALID_BUG_ALIAS => random_string(20);
use constant PRIVS_USER => 'QA_Selenium_TEST';

sub attach {
    my ($id, $override) = @_;
    my %fields = (
        ids  => [$id],
        data => 'data-' . random_string(100),
        file_name => 'file_name-' . random_string(60),
        summary => 'summary-' . random_string(100),
        content_type => 'text/plain',
        comment => 'comment-' . random_string(100),
    );

    foreach my $key (keys %{ $override || {} }) {
        my $value = $override->{$key};
        if (defined $value) {
            $fields{$key} = $value;
        }
        else {
            delete $fields{$key};
        }
    }
    return \%fields;
}

my ($public_bug, $private_bug) =
    $xmlrpc->bz_create_test_bugs('private');
my $public_id = $public_bug->{id};
my $private_id = $private_bug->{id};

my @tests = (
    # Permissions
    { args  => attach($public_id),
      error => 'You must log in',
      test  => 'Logged-out user cannot add an attachment to a public bug',
    },
    { args  => attach($private_id),
      error => "You must log in",
      test  => 'Logged-out user cannot add an attachment to a private bug',
    },
    { user  => 'editbugs',
      args  => attach($private_id),
      error => "not authorized to access",
      test  => "Editbugs user can't add an attachment to a private bug",
    },

    # Test ID parameter
    { user  => 'unprivileged',
      args  => attach(undef, { ids => undef }),
      error => 'a ids argument',
      test  => 'Failing to pass the "ids" param fails',
    },
    { user  => 'unprivileged',
      args  => attach(INVALID_BUG_ID),
      error => "not a valid bug number",
      test  => 'Passing invalid bug id returns error "Invalid Bug ID"',
    },
    { user  => 'unprivileged',
      args  => attach(''),
      error => "You must enter a valid bug number",
      test  => 'Passing empty bug id returns error "Invalid Bug ID"',
    },
    { user  => 'unprivileged',
      args  => attach(INVALID_BUG_ALIAS),
      error => "nor an alias to a bug",
      test  => 'Passing invalid bug alias returns error "Invalid Bug Alias"',
    },

    # Test Comment parameter
    { user  => 'unprivileged',
      args  => attach($public_id, { data => undef }),
      error => 'a data argument',
      test  => 'Failing to pass the "data" parameter fails',
    },
    { user  => 'unprivileged',
      args  => attach($public_id, { data => '' }),
      error => "The file you are trying to attach is empty",
      test  => 'Passing empty data fails',
    },
    { user  => 'unprivileged',
      args  => attach($public_id, { data => random_string(300_000) }),
      error => "Attachments cannot be more than",
      test  => "Passing an attachment that's too large fails",
    },

    # Test the private parameter
    { user  => 'unprivileged',
      args  => attach($public_id, { is_private => 1 }),
      error => 'attachments as private',
      test  => 'Unprivileged user cannot add a private attachment'
    },

    # Content-type
    { user  => 'unprivileged',
      args  => attach($public_id, { content_type => 'foo/bar' }),
      error => "Valid types must be of the form",
      test  => "Well-formed but invalid content type fails",
    },
    { user  => 'unprivileged',
      args  => attach($public_id, { content_type => undef }),
      error => 'Valid types must be of the form',
      test  => "Failing to pass content_type fails",
    },
    { user  => 'unprivileged',
      args  => attach($public_id, { content_type => '' }),
      error => 'Valid types must be of the form',
      test  => "Empty content type fails",
    },

    # Summary
    { user  => 'unprivileged',
      args  => attach($public_id, { summary => undef }),
      error => 'You must enter a description for the attachment',
      test  => "Failing to pass summary fails",
    },
    { user  => 'unprivileged',
      args  => attach($public_id, { summary => '' }),
      error => 'You must enter a description for the attachment',
      test  => "Empty summary fails",
    },

    # Filename
    { user  => 'unprivileged',
      args  => attach($public_id, { file_name => undef }),
      error => 'You did not specify a file to attach',
      test  => "Failing to pass file_name fails",
    },
    { user  => 'unprivileged',
      args  => attach($public_id, { file_name => '' }),
      error => 'You did not specify a file to attach',
      test  => "Empty file_name fails",
    },

    # Success tests
    { user => 'unprivileged',
      args => attach($public_id),
      test => 'Unprivileged user can add an attachment to a public bug',
    },
    { user => 'unprivileged',
      args => attach($public_id, { is_patch => 1, content_type => undef }),
      test => 'Attaching a patch with no content type works',
    },
    { user => 'unprivileged',
      args => attach($public_id, { is_patch => 1,
                     content_type => 'application/octet-stream' }),
      test => 'Attaching a patch with a bad content_type works',
    },
    { user => PRIVS_USER,
      args => attach($private_id),
      test => 'Privileged user can add an attachment to a private bug',
    },
    { user => PRIVS_USER,
      args => attach($public_id, { is_private => 1 }),
      test => 'Insidergroup user can add a private attachment',
    },
);

$jsonrpc_get->bz_call_fail('Bug.add_attachment', attach($public_id),
    'must use HTTP POST', 'add_attachment fails over GET');

foreach my $rpc ($jsonrpc, $xmlrpc) {
    $rpc->bz_run_tests(tests => \@tests, method => 'Bug.add_attachment',
                       post_success => \&post_success, pre_call => \&pre_call);
}

# We have to encode data manually when using JSON-RPC, else it fails.
sub pre_call {
    my ($t, $rpc) = @_;
    return if !$rpc->isa('QA::RPC::JSONRPC');
    return if !defined $t->{args}->{data};

    $t->{args}->{data} = encode_base64($t->{args}->{data}, '');
}

sub post_success {
    my ($call, $t, $rpc) = @_;

    my $ids = [ keys %{ $call->result->{attachments} } ];
    $call = $rpc->bz_call_success("Bug.attachments", {attachment_ids => $ids});
    my $attachments = $call->result->{attachments};

    foreach my $id (keys %$attachments) {
        my $attachment = $attachments->{$id};
        if ($t->{args}->{is_private}) {
            ok($attachment->{is_private},
               $rpc->TYPE . ": Attachment $id is private");
        }
        else {
            ok(!$attachment->{is_private},
               $rpc->TYPE . ": Attachment $id is NOT private");
        }

        if ($t->{args}->{is_patch}) {
            is($attachment->{content_type}, 'text/plain',
               $rpc->TYPE . ": Patch $id content type is text/plain");
        }
        else {
            is($attachment->{content_type}, $t->{args}->{content_type},
               $rpc->TYPE . ": Attachment $id content type is correct");
        }

        if ($rpc->isa('QA::RPC::JSONRPC')) {
            # We encoded data in pre_call(), so we have to restore it to its original content.
            $t->{args}->{data} = decode_base64($t->{args}->{data});
            $attachment->{data} = decode_base64($attachment->{data});
        }
        is($attachment->{data}, $t->{args}->{data},
           $rpc->TYPE . ": Attachment $id data is correct");
    }
}
