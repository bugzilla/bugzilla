# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Data::Dumper;
use QA::Util;
use QA::Tests qw(PRIVATE_BUG_USER STANDARD_BUG_TESTS);
use Storable qw(dclone);
use Test::More tests => 921;

use constant NONEXISTANT_BUG => 12_000_000;

###############
# Subroutines #
###############

# We have to generate different values for each RPC client, so we
# have a function to generate the tests for each client.
sub get_tests {
    my ($config, $rpc) = @_;

    # update doesn't support logged-out users.
    my @tests = grep { $_->{user} } @{ STANDARD_BUG_TESTS() };

    my ($public_bug, $second_bug) = $rpc->bz_create_test_bugs();
    my ($public_id, $second_id) = ($public_bug->{id}, $second_bug->{id});

    my $comment_call = $rpc->bz_call_success(
        'Bug.comments', { ids => [$public_id, $second_id] });
    $public_bug->{comment} =
        $comment_call->result->{bugs}->{$public_id}->{comments}->[0];
    $second_bug->{comment} =
        $comment_call->result->{bugs}->{$second_id}->{comments}->[0];

    push(@tests, (
        { args  => { ids => [$public_id] },
          error => 'You must log in',
          test  => 'Logged-out users cannot call update' },

        # FIXME: We need a permissions test for canedit, but it's so uncommonly
        #        used that it's not a high priority.
    ));

    my %valid = valid_values($config, $public_bug, $second_bug);
    my $valid_value_tests = valid_values_to_tests(\%valid, $public_bug);
    push(@tests, @$valid_value_tests);

    my %invalid = invalid_values($public_bug, $second_bug);
    my $invalid_value_tests = invalid_values_to_tests(\%invalid, $public_bug);
    push(@tests, @$invalid_value_tests);

    return \@tests;
}

sub valid_values {
    my ($config, $public_bug, $second_bug) = @_;

    my $admin = $config->{'admin_user_login'};
    my $second_id = $second_bug->{id};
    my $comment_id = $public_bug->{comment}->{id};
    my $bug_uri = $config->{browser_url} . '/'
                  . $config->{bugzilla_installation} . '/show_bug.cgi?id=';

    my %values = (
        alias => [
            { value => random_string(20) },
        ],
        assigned_to => [
            { value => $config->{'unprivileged_user_login'} }
        ],
        blocks => [
            { value => { set => [$second_id] },
              added => $second_id,
              test  => 'set to second bug' },
            { value => { remove => [$second_id] },
              added => '', removed => $second_id,
              test  =>  'remove second bug' },
            { value => { add => [$second_id] },
              added => $second_id, removed => '',
              test  => 'add second bug' },
            { value => { set => [] },
              added => '', removed => $second_id,
              test  => 'set to nothing' },
        ],

        cc => [
            { value => { add => [$admin] },
              added => $admin, removed => '',
              test  => 'add admin' },
            { value => { remove => [$admin] },
              added => '', removed => $admin,
              test  =>  'remove admin' },
            { value => { remove => [$admin] },
              test  => "removing user who isn't on the list works",
              no_changes => 1 },
        ],

        is_cc_accessible => [
            { value => 0, test => 'set to 0' },
            { value => 1, test => 'set to 1' },
        ],

        comment => [
            { value => { body => random_string(100) }, test => 'public' },
            { value => { body => random_string(100), is_private => 1 },
              user  => PRIVATE_BUG_USER, test => 'private' },
        ],

        comment_is_private => [
            { value => { $comment_id => 1 },
              user  => PRIVATE_BUG_USER, test => 'make description private' },
            { value => { $comment_id => 0 },
              user  => PRIVATE_BUG_USER, test => 'make description public' },
        ],

        component => [
            { value => 'c2' }
        ],

        deadline => [
            { value => '2037-01-01' },
            { value => '', removed => '2037-01-01', test => 'remove' },
        ],

        dupe_of => [
            { value => $second_id },
        ],

        estimated_time => [
            { value => '10.0' },
            { value => '0.0', removed => '10.0', test => 'set to zero' },
        ],

        groups => [
            { value => { add => ['Master'] },
              user => 'admin', added => 'Master', test => 'add Master' },
            { value => { remove => ['Master'] },
              user => 'admin', added => '', removed => 'Master',
              test => 'remove Master' },
        ],

        keywords => [
            { value => { add => ['test-keyword-1'] },
              test => 'add one', added => 'test-keyword-1' },
            { value => { set => ['test-keyword-1', 'test-keyword-2'] },
              test  => 'set two', added => 'test-keyword-2' },
            { value => { remove => ['test-keyword-1'] },
              removed => 'test-keyword-1', added => '',
              test  => 'remove one' },
            { value => { set => [] },
              removed => 'test-keyword-2', added => '',
              test  => 'set to empty' },
            { value => { remove => ['test-keyword-2'] },
              test  => 'removing removed keyword does nothing',
              no_changes => 1 },
        ],

        op_sys => [
            { value => 'All' },
        ],

        platform => [
            { value => 'All' },
        ],

        priority => [
            { value => 'Normal' },
        ],

        product => [
            { value => 'C2 Forever',
              extra => {
                component => 'Helium', version => 'unspecified',
                target_milestone => '---',
              },
              test  => 'move to C2 Forever'
            },
            # This also tests that the extra fields transfer over properly
            # when they have identical names in both products.
            { value => $public_bug->{product},
              extra => { component => $public_bug->{component} },
              test  => 'move back to original product' },
        ],

        qa_contact => [
            { value => $admin },
            { value => '', test => 'set blank', removed => $admin },
            # Reset to the original so that reset_qa_contact can also be tested.
            { value => $public_bug->{qa_contact} },
        ],

        remaining_time => [
            { value => '1000.50' },
            { value => 0 },
        ],

        reset_assigned_to => [
            { value => 1, field => 'assigned_to',
              added => $config->{permanent_user} },
        ],

        reset_qa_contact => [
            { value => 1, field => 'qa_contact', added => '' },
        ],

        resolution => [
            { value => 'FIXED', extra => { status => 'RESOLVED' },
              test => 'to RESOLVED FIXED' },
            { value => 'INVALID', test => 'just resolution' },
        ],

        see_also => [
            { value => { add => [$bug_uri . $second_id] },
              added => $bug_uri . $second_id, removed => '',
              test => 'add local bug URI' },
            { value => { remove => [$bug_uri . $second_id] },
              removed => $bug_uri . $second_id, added => '',
              test => 'remove local bug URI' },
            { value => { remove => ['http://landfill.bugzilla.org/bugzilla-tip/show_bug.cgi?id=1'] },
              no_changes => 1,
              test => 'removing non-existent URI works' },
            { value => { add => [''] },
              no_changes => 1,
              test  => 'adding an empty string to see_also does nothing' },
            { value => { add => [undef] },
              no_changes => 1,
              test  => 'adding a null to see_also does nothing' },
        ],

        status => [
            # At this point, due to previous tests, the status is RESOLVED,
            # so changing to CONFIRMED is our only real option if we want to
            # test a simple open status.
            { value => 'CONFIRMED' },
        ],

        severity => [
            { value => 'critical' },
        ],

        summary => [
            { value => random_string(100) },
        ],

        target_milestone => [
            { value => 'AnotherMS2' },
        ],

        url => [
            { value => 'http://' . random_string(20) . '/' },
        ],

        version => [
            { value => 'Another2' },
        ],

        whiteboard => [
            { value => random_string(1000) },
        ],

        work_time => [
            # FIXME: work_time really needs to start showing up in the changes hash.
            { value => '1.2', no_changes => 1 },
            { value => '-1.2', test => 'negative value', no_changes => 1 },
        ],
    );

    $values{depends_on} = $values{blocks};
    $values{is_creator_accessible} = $values{is_cc_accessible};

    return %values;
};

sub valid_values_to_tests {
    my ($valid_values, $public_bug) = @_;

    my @tests;
    foreach my $field (sort keys %$valid_values) {
        my @tests_valid = @{ $valid_values->{$field} };
        foreach my $item (@tests_valid) {
            my $desc = $item->{test} || 'valid value';
            my %args = (
                ids => [$public_bug->{id}],
                $field => $item->{value},
                %{ $item->{extra} || {} },
            );
            my %test = ( user => 'editbugs', args => \%args, field => $field,
                         test => "$field: $desc" );
            foreach my $item_field (qw(no_changes added removed field user)) {
                next if !exists $item->{$item_field};
                $test{$item_field} = $item->{$item_field};
            }
            push(@tests, \%test);
        }
    }

    return \@tests;
}

sub invalid_values {
    my ($public_bug, $second_bug) = @_;

    my $public_id = $public_bug->{id};
    my $second_id = $second_bug->{id};

    my $comment_id = $public_bug->{comment}->{id};
    my $second_comment_id = $second_bug->{comment}->{id};

    my %values = (
        alias => [
            { value => random_string(41),
              error => 'aliases cannot be longer than',
              test  => 'alias cannot be too long' },
            { value => $second_bug->{alias},
              error => 'has already taken the alias',
              test  => 'duplicate alias fails' },
            { value => 123456,
              error => 'at least one letter',
              test  => 'numeric alias fails' },
            { value => random_string(20), ids => [$public_id, $second_id],
              error => 'aliases when modifying multiple',
              test  => 'setting alias on multiple bugs fails' },
        ],

        assigned_to => [
            { value => random_string(20),
              error => 'There is no user named',
              test  => 'changing assigned_to to invalid user fails' },
            # FIXME: Also check strict_isolation at some point in the future, perhaps.
        ],

        blocks => [
            { value => { add => [NONEXISTANT_BUG] },
              error => 'does not exist',
              test  => 'Non-existent bug number fails in deps' },
            { value => { add => [$public_id] },
              error => 'block itself or depend on itself',
              test  => "can't add this bug itself in a dep field" },
            # FIXME: Could use strict_isolation checks at some point.
            # FIXME: Could use a dependency_loop_multi test.
        ],

        cc => [
            { value => { add => [random_string(20)] },
              error => 'There is no user named',
              test  => 'adding invalid user to cc fails' },
            { value => { remove => [random_string(20)] },
              error => 'There is no user named',
              test  => 'removing invalid user from cc fails' },
        ],

        comment => [
            { value => { body => random_string(100_000) },
              error => 'cannot be longer',
              test  => 'comment too long' },
            { value => { body => random_string(100), is_private => 1 },
              error => 'comments or attachments as private',
              test  => 'normal user cannot add private comments' },
        ],

        comment_is_private => [
            { value => { $comment_id => 1 },
              error => 'comments or attachments as private',
              test  => 'normal user cannot make a comment private' },
            { value => { $second_comment_id => 1 },
              error => 'You tried to modify the privacy of comment',
              user  => PRIVATE_BUG_USER,
              test  => 'cannot change privacy on a comment on another bug' },
        ],

        component => [
            { value => '',
              error => 'you must first choose a component',
              test  => 'empty component fails' },
            { value => random_string(20),
              error => 'There is no component named',
              test  => 'invalid component fails' },
        ],

        deadline => [
            { value => random_string(20),
              error => 'is not a legal date',
              test  => 'Non-date fails in deadline' },
            { value => '2037',
              error => 'is not a legal date',
              test  => 'year alone fails in deadline' },
        ],

        dupe_of => [
            { value => undef,
              error => 'dup_id was not defined',
              test  => 'undefined dupe_of fails' },
            { value => NONEXISTANT_BUG,
              error => 'does not exist',
              test  => 'Cannot dup to a nonexistant bug' },
            { value => $public_id,
              error => 'as a duplicate of itself',
              test  => 'Cannot dup bug to itself' },
        ],

        estimated_time => [
            { value => -1,
              error => 'less than the minimum allowable value',
              test  => 'negative estimated_time fails' },
            { value => 100_000_000,
              error => 'more than the maximum allowable value',
              test  => 'too-large estimated_time fails' },
            { value => random_string(20),
              error => 'is not a numeric value',
              test  => 'non-numeric estimated_time fails' },
            # We use PRIVATE_BUG_USER because he can modify the bug, but
            # can't change time-tracking fields.
            { value => '100', user => PRIVATE_BUG_USER,
              error => 'only a user with the required permissions',
              test  => 'non-timetracker can not set estimated_time' },
        ],

        groups => [
            { value => { add => ['Master'] },
              error => 'either this group does not exist, or you are not allowed to restrict bugs to this group',
              test  => "adding group we don't have access to but is valid fails" },
            { value => { add => ['QA-Selenium-TEST'] },
              error => 'either this group does not exist, or you are not allowed to restrict bugs to this group',
              test  => 'adding valid group that is not in this product fails' },
            { value => { add => [random_string(20)] },
              error => 'either this group does not exist, or you are not allowed to restrict bugs to this group',
              test  => 'adding non-existent group fails' },
            { value => { remove => [random_string(20)] },
              error => 'either this group does not exist, or you are not allowed to remove bugs from this group',
              test => 'removing non-existent group fails' },
        ],

        keywords => [
            { value => { add => [random_string(20)] },
              error => 'The legal keyword names are listed here',
              test  => 'adding invalid keyword fails' },
            { value => { remove => [random_string(20)] },
              error => 'The legal keyword names are listed here',
              test  => 'removing invalid keyword fails' },
            { value => { set => [random_string(20)] },
              error => 'The legal keyword names are listed here',
              test  => 'setting invalid keyword fails' },
        ],

        op_sys => [
            { value => random_string(20),
              error => 'There is no',
              test  => 'invalid op_sys fails' },
            { value => '',
              error => 'You must select/enter',
              test => 'blank op_sys fails' },
        ],

        product => [
            { value => random_string(60),
              error => "does not exist or you aren't authorized",
              test  => 'invalid product fails' },
            { value => '',
              error => 'You must select/enter a product',
              test  => 'moving to blank product fails' },
            { value => 'TestProduct',
              error => 'There is no component named',
              test  => 'moving products without other fields fails' },
            { value => 'QA-Selenium-TEST',
              extra => { component => 'QA-Selenium-TEST' },
              error => "does not exist or you aren't authorized",
              test  => 'moving to inaccessible product fails' },
            { value => 'QA Entry Only',
              error => "does not exist or you aren't authorized",
              test  => 'moving to product where ENTRY is denied fails' },
        ],

        qa_contact => [
            { value => random_string(20),
              error => 'There is no user named',
              test  => 'changing qa_contact to invalid user fails' },
        ],

        remaining_time => [
            { value => -1,
              error => 'less than the minimum allowable value',
              test  => 'negative remaining_time fails' },
            { value => 100_000_000,
              error => 'more than the maximum allowable value',
              test  => 'too-large remaining_time fails' },
            { value => random_string(20),
              error => 'is not a numeric value',
              test  => 'non-numeric remaining_time fails' },
            # We use PRIVATE_BUG_USER because he can modify the bug, but
            # can't change time-tracking fields.
            { value => '100', user => PRIVATE_BUG_USER,
              error => 'only a user with the required permissions',
              test  => 'non-timetracker can not set remaining_time' },
        ],

        # We do all the failing resolution tests on the second bug,
        # because we want to be sure that we're starting from an open
        # status.
        resolution => [
            { value => random_string(20), ids => [$second_id],
              extra => { status => 'RESOLVED' },
              error => 'There is no Resolution named',
              test  => 'invalid resolution fails' },
            { value => 'FIXED', ids => [$second_id],
              error => 'You cannot set a resolution for open bugs',
              test  => 'setting resolution on open bug fails' },
            { value => 'DUPLICATE', ids => [$second_id],
              extra => { status => 'RESOLVED' },
              error => 'id to mark this bug as a duplicate',
              test  => 'setting DUPLICATE without dup_id fails' },
            { value => '', ids => [$second_id],
              extra => { status => 'RESOLVED' },
              error => 'A valid resolution is required',
              test => 'blank resolution fails with closed status' },
        ],

        see_also => [
            { value => { add => [random_string(20)] },
              error => 'is not a valid bug number nor an alias',
              test  => 'random string fails in see_also' },
            { value => { add => ['http://landfill.bugzilla.org/'] },
              error => 'See Also URLs should point to one of',
              test  => 'no show_bug.cgi in see_also URI' },
        ],

        status => [
            { value => random_string(20),
              error => 'There is no status named',
              test  => 'invalid status fails' },
            { value => '',
              error => 'You must select/enter a status',
              test => 'blank status fails' },
            # We use the second bug for this because we can guarantee that
            # it is open.
            { value => 'VERIFIED', ids => [$second_id],
              extra => { resolution => 'FIXED' },
              error => 'You are not allowed to change the bug status from',
              test  => 'invalid transition fails' },
        ],

        summary => [
            { value => random_string(300),
              error => 'The text you entered in the Summary field is too long',
              test  => 'too-long summary fails' },
            { value => '',
              error => 'You must enter a summary for this bug',
              test  => 'blank summary fails' },
        ],

        work_time => [
            { value => 100_000_000,
              error => 'more than the maximum allowable value',
              test  => 'too-large work_time fails' },
            { value => random_string(20),
              error => 'is not a numeric value',
              test  => 'non-numeric work_time fails' },
            # We use PRIVATE_BUG_USER because he can modify the bug, but
            # can't change time-tracking fields.
            { value => '10', user => PRIVATE_BUG_USER,
              error => 'only a user with the required permissions',
              test  => 'non-timetracker can not set work_time' },
        ],
    );

    $values{depends_on} = $values{blocks};

    foreach my $field (qw(platform priority severity target_milestone version))
    {
        my $tests = dclone($values{op_sys});
        foreach my $test (@$tests) {
            $test->{test} =~ s/op_sys/$field/g;
        }
        $values{$field} = $tests;
    }

    return %values;
}

sub invalid_values_to_tests {
    my ($invalid_values, $public_bug) = @_;

    my @tests;
    foreach my $field (sort keys %$invalid_values) {
        my @tests_invalid = @{ $invalid_values->{$field} };
        foreach my $item (@tests_invalid) {
            my %args = (
                ids => $item->{ids} || [$public_bug->{id}],
                $field => $item->{value},
                %{ $item->{extra} || {} },
            );
            push(@tests, { user => $item->{user} || 'editbugs',
                           args => \%args,
                           error => $item->{error},
                           test => $item->{test} });
        }
    }

    return \@tests;
}

###############
# Main Script #
###############

my ($config, $xmlrpc, $jsonrpc, $jsonrpc_get) = get_rpc_clients();

$jsonrpc_get->bz_call_fail('Bug.update',
    { ids => ['public_bug'] },
    'must use HTTP POST', 'update fails over GET');

sub post_success {
    my ($call, $t, $rpc) = @_;
    return if $t->{no_changes};
    my $field = $t->{field};
    return if !$field;

    my @bugs = @{ $call->result->{bugs} };
    foreach my $bug (@bugs) {
        if ($field =~ /^comment/) {
            _check_comment($bug, $field, $t, $rpc);
        }
        else {
            _check_changes($bug, $field, $t);
        }
    }
}

sub _check_changes {
    my ($bug, $field, $t) = @_;

    my $changes = $bug->{changes}->{$field};
    ok(defined $changes, "$field was changed")
      or diag Dumper($bug, $t);

    my $new_value = $t->{added};
    $new_value = $t->{args}->{$field} if !defined $new_value;
    _test_value($changes->{added}, $new_value, $field, 'added');

    if (defined $t->{removed}) {
        _test_value($changes->{removed}, $t->{removed}, $field, 'removed');
    }
}

sub _test_value {
    my ($got, $expected, $field, $type) = @_;
    if ($field eq 'estimated_time' or $field eq 'remaining_time') {
        cmp_ok($got, '==', $expected, "$field: $type is correct");
    }
    else {
        is($got, $expected, "$field: $type is correct");
    }
}

sub _check_comment {
    my ($bug, $field, $t, $rpc) = @_;
    my $bug_id = $bug->{id};
    my $call = $rpc->bz_call_success('Bug.comments', { ids => [$bug_id] });
    my $comments = $call->result->{bugs}->{$bug_id}->{comments};

    if ($field eq 'comment_is_private') {
        my $first_private = $comments->[0]->{is_private};
        my ($expected) = values %{ $t->{args}->{comment_is_private} };
        cmp_ok($first_private, '==', $expected,
               'description privacy is correct');
    }
    else {
        my $last_comment = $comments->[-1];
        my $expected = $t->{args}->{comment}->{body};
        is($last_comment->{text}, $expected, 'comment added correctly');
    }

}

foreach my $rpc ($jsonrpc, $xmlrpc) {
    $rpc->bz_run_tests(tests => get_tests($config, $rpc),
        method => 'Bug.update', post_success => \&post_success);
}
