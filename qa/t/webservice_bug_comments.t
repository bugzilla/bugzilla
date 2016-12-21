# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

##########################################
# Test for xmlrpc call to Bug.comments() #
##########################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use DateTime;
use QA::Util;
use QA::Tests qw(STANDARD_BUG_TESTS PRIVATE_BUG_USER);
use Test::More tests => 331;
my ($config, @clients) = get_rpc_clients();

# These gets populated when we call Bug.add_comment.
our $creation_time;
our %comments = (
    public_comment_public_bug  => 0,
    public_comment_private_bug  => 0,
    private_comment_public_bug  => 0,
    private_comment_private_bug => 0,
);

sub test_comments {
    my ($comments_returned, $call, $t, $rpc) = @_;

    my $comment = $comments_returned->[0];
    ok($comment->{bug_id}, "bug_id exists");
    # FIXME: At some point we should test attachment_id here.

    if ($t->{args}->{comment_ids}) {
        my $expected_id = $t->{args}->{comment_ids}->[0];
        is($comment->{id}, $expected_id, "comment id is correct");

        my %reverse_map = reverse %comments;
        my $expected_text = $reverse_map{$expected_id};
        is($comment->{text}, $expected_text, "comment has the correct text");

        my $priv_login = $rpc->bz_config->{PRIVATE_BUG_USER . '_user_login'};
        is($comment->{creator}, $priv_login, "comment creator is correct");


        my $creation_day;
        if ($rpc->isa('QA::RPC::XMLRPC')) {
            $creation_day = $creation_time->ymd('');
        }
        else {
            $creation_day = $creation_time->ymd;
        }
        like($comment->{time}, qr/^\Q${creation_day}\ET\d\d:\d\d:\d\d/,
             "comment time has the right format");
    }
    else {
        foreach my $field (qw(id text creator time)) {
            ok(defined $comment->{$field}, "$field is defined");
        }
    }
}

################
# Bug ID Tests #
################

sub post_bug_success {
    my ($call, $t) = @_;
    my @bugs = values %{ $call->result->{bugs} };
    is(scalar @bugs, 1, "Got exactly one bug");
    my @comments = map { @{ $_->{comments} } } @bugs;
    test_comments(\@comments, @_);
}

foreach my $rpc (@clients) {
    $rpc->bz_run_tests(tests => STANDARD_BUG_TESTS, method => 'Bug.comments',
                       post_success => \&post_bug_success);
}

####################
# Comment ID Tests #
####################

# First, create comments using add_comment.
my @add_comment_tests;
foreach my $key (keys %comments) {
    $key =~ /^([a-z]+)_comment_(\w+)$/;
    my $is_private = ($1 eq 'private' ? 1 : 0);
    my $bug_alias = $2;
    push(@add_comment_tests, { args => { id => $bug_alias, comment => $key,
                                         private => $is_private },
                               test => "Add comment: $key",
                               user => PRIVATE_BUG_USER });
}

# Set the comment id for each comment that we add, so we can test getting
# them back, later.
sub post_add {
    my ($call, $t) = @_;
    my $key = $t->{args}->{comment};
    $comments{$key} = $call->result->{id};
}

$creation_time = DateTime->now();
# We only need to create these comments once, with one of the interfaces.
$clients[0]->bz_run_tests(
    tests => \@add_comment_tests, method => 'Bug.add_comment',
    post_success => \&post_add);

# Now check access on each private and public comment

my @comment_tests = (
    # Logged-out user
    { args => { comment_ids => [$comments{'public_comment_public_bug'}] },
      test => 'Logged-out user can access public comment on public bug by id',
    },
    { args  => { comment_ids => [$comments{'private_comment_public_bug'}] },
      test  => 'Logged-out user cannot access private comment on public bug',
      error => 'is private',
    },
    { args  => { comment_ids => [$comments{'public_comment_private_bug'}] },
      test  => 'Logged-out user cannot access comments by id on private bug',
      error => 'You are not authorized to access',
    },
    { args  => { comment_ids => [$comments{'private_comment_private_bug'}] },
      test  => 'Logged-out user cannot access private comment on private bug',
      error => 'You are not authorized to access',
    },

    # Logged-in, unprivileged user.
    { user => 'unprivileged',
      args => { comment_ids => [$comments{'public_comment_public_bug'}] },
      test => 'Logged-in user can see a public comment on a public bug by id',
    },
    { user  => 'unprivileged',
      args  => { comment_ids => [$comments{'private_comment_public_bug'}] },
      test  => 'Logged-in user cannot access private comment on public bug',
      error => 'is private',
    },
    { user  => 'unprivileged',
      args  => { comment_ids => [$comments{'public_comment_private_bug'}] },
      test  => 'Logged-in user cannot access comments by id on private bug',
      error => "You are not authorized to access",
    },
    { user  => 'unprivileged',
      args  => { comment_ids => [$comments{'private_comment_private_bug'}] },
      test  => 'Logged-in user cannot access private comment on private bug',
      error => "You are not authorized to access",
    },

    # User who can see private bugs and private comments
    { user => PRIVATE_BUG_USER,
      args => { comment_ids => [$comments{'private_comment_public_bug'}] },
      test => PRIVATE_BUG_USER . ' can see private comment on public bug',
    },
    { user  => PRIVATE_BUG_USER,
      args  => { comment_ids => [$comments{'private_comment_private_bug'}] },
      test  => PRIVATE_BUG_USER . ' can see private comment on private bug',
    },
);

sub post_comments {
    my ($call) = @_;
    my @comments = values %{ $call->result->{comments} };
    is(scalar @comments, 1, "Got exactly one comment");
    test_comments(\@comments, @_);
}

foreach my $rpc (@clients) {
    $rpc->bz_run_tests(tests => \@comment_tests, method => 'Bug.comments',
                       post_success => \&post_comments);
}
