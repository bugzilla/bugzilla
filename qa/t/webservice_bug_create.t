# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

########################################
# Test for xmlrpc call to Bug.create() #
########################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Storable qw(dclone);
use Test::More tests => 293;
use QA::Util;
use QA::Tests qw(create_bug_fields PRIVATE_BUG_USER);

my ($config, $xmlrpc, $jsonrpc, $jsonrpc_get) = get_rpc_clients();

########################
# Bug.create() testing #
########################

my $bug_fields = create_bug_fields($config);

# hash to contain all the possible $bug_fields values that
# can be passed to createBug()
my $fields = {
    summary => {
        undefined => {
            faultstring => 'You must enter a summary for this bug',
            value       => undef
        },
    },

    product => {
        undefined => { faultstring => 'You must select/enter a product.', value => undef },
        invalid =>
            { faultstring => 'does not exist', value => 'does-not-exist' },
    },

    component => {
        undefined => {
            faultstring => 'you must first choose a component',
            value       => undef
        },
        invalid => {
            faultstring => "There is no component named 'does-not-exist'",
            value => 'does-not-exist'
        },
    },

    version => {
        undefined =>
            { faultstring => 'You must select/enter a version.', value => undef },
        invalid => {
            faultstring => "There is no version named 'does-not-exist' in the",
            value       => 'does-not-exist'
        },
    },
    platform => {
        undefined =>
            { faultstring => 'You must select/enter a Hardware.',
              value => '' },
        invalid => {
            faultstring => "There is no Hardware named 'does-not-exist'.",
            value       => 'does-not-exist'
        },
    },

    status => {
        invalid => {
            faultstring => "There is no status named 'does-not-exist'",
            value       => 'does-not-exist'
        },
    },

    severity => {
        undefined =>
            { faultstring => 'You must select/enter a Severity.',
              value => '' },
        invalid => {
            faultstring => "There is no Severity named 'does-not-exist'.",
            value       => 'does-not-exist'
        },
    },

    priority => {
        undefined =>
            { faultstring => 'You must select/enter a Priority.',
              value => '' },
        invalid => {
            faultstring => "There is no Priority named 'does-not-exist'.",
            value       => 'does-not-exist'
        },
    },

    op_sys => {
        undefined => {
            faultstring => 'You must select/enter a OS.',
            value       => ''
        },
        invalid => {
            faultstring => "There is no OS named 'does-not-exist'.",
            value       => 'does-not-exist'
        },
    },

    cc => {
        invalid => {
            faultstring => 'not a valid username',
            value       => ['nonuserATbugillaDOTorg']
        },
    },

    assigned_to => {
        invalid => {
            faultstring => "There is no user named 'does-not-exist'",
            value       => 'does-not-exist'
        },
    },
    qa_contact => {
        invalid => {
            faultstring => "There is no user named 'does-not-exist'",
            value       => 'does-not-exist'
        },
    },
    alias => {
        long => {
            faultstring => 'Bug aliases cannot be longer than 20 characters',
            value       => 'MyyyyyyyyyyyyyyyyyyBugggggggggggggggggggggg'
        },
        existing => {
            faultstring => 'already taken the alias',
            value       => 'public_bug'
        },
        numeric => {
            faultstring => 'aliases cannot be merely numbers',
            value       => '12345'
        },
        commma_or_space_separated => {
            faultstring => 'contains one or more commas or spaces',
            value       => 'Bug 12345'
        },

    },
    groups => {
        non_existent => {
            faultstring => 'either this group does not exist, or you are not allowed to restrict bugs to this group',
            value => [random_string(20)],
        },
    },
    comment_is_private => {
        invalid => {
             faultstring => 'you are not allowed to.+comments.+private',
             value => 1,
        }
    },
};

$jsonrpc_get->bz_call_fail('Bug.create', $bug_fields,
    'must use HTTP POST', 'create fails over GET');

my @tests = (
    { args  => $bug_fields,
      error => "You must log in",
      test  => "Cannot file bugs as a logged-out user",
    },
    { user => PRIVATE_BUG_USER,
      args => { %$bug_fields, product => 'QA-Selenium-TEST',
                component => 'QA-Selenium-TEST',
                target_milestone => 'QAMilestone',
                version => 'QAVersion',
                groups => ['QA-Selenium-TEST'],
                # These are set here because we can't actually set them,
                # and we need the values to be correct for post_success.
                qa_contact => $config->{PRIVATE_BUG_USER . '_user_login'},
                status => 'UNCONFIRMED' },
      test => "Authorized user can file a bug against a group",
    },
    { user => PRIVATE_BUG_USER,
      args => { %$bug_fields, comment_is_private => 1,
                # These are here because PRIVATE_BUG_USER can't set them
                # and we need their values to be correct for post_success.
                assigned_to => $config->{'permanent_user'},
                qa_contact => '',
                status => 'UNCONFIRMED' },
      test => "Insider can create a private description"
    },
    { user => 'editbugs',
      args => $bug_fields,
      test => "Creating a bug with standard values succeeds",
    },
);

# Convert the $fields tests into standard bz_run_tests format.
foreach my $field (sort keys %$fields) {
    my $test_values = $fields->{$field};
    foreach my $test_name (sort keys %$test_values) {
        my $input_fields = dclone($bug_fields);
        my $check_value = $test_values->{$test_name}->{value};
        my $error       = $test_values->{$test_name}->{faultstring};
        $input_fields->{$field} = $check_value;
        my $test = { user => 'editbugs', args => $input_fields,
                     error => $error,
                     test => "$field $test_name: fails as expected" };
        push(@tests, $test);
    }
}

sub post_success {
    my ($call, $t, $rpc) = @_;

    my $id = $call->result->{id};
    ok($id, $rpc->TYPE . ": Result has an id: $id");

    my $get_call = $rpc->bz_call_success('Bug.get', { ids => [$id] });
    my $bug = $get_call->result->{bugs}->[0];

    my $expect = dclone $t->{args};

    my $comment_is_private = delete $expect->{comment_is_private};
    $expect->{creator} = $rpc->bz_config->{$t->{user} . '_user_login'};

    my @fields = keys %$expect;
    $rpc->bz_test_bug(\@fields, $bug, $expect, $t);

    my $comment_call = $rpc->bz_call_success('Bug.comments', { ids => [$id] });
    my $comment = $comment_call->result->{bugs}->{$id}->{comments}->[0];
    is($comment->{is_private} ? 1 : 0, $comment_is_private ? 1 : 0,
       $rpc->TYPE . ": comment privacy is correct");
}

foreach my $rpc ($jsonrpc, $xmlrpc) {
    $rpc->bz_run_tests(tests => \@tests, method => 'Bug.create',
                       post_success => \&post_success);
}
