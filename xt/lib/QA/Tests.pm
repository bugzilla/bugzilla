# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# -*- Mode: perl; indent-tabs-mode: nil -*-

package QA::Tests;

use 5.14.0;
use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/../../lib", "$RealBin/../../../local/lib/perl5";

use parent qw(Exporter);

our @EXPORT_OK = qw(
  PRIVATE_BUG_USER
  STANDARD_BUG_TESTS
  bug_tests
  create_bug_fields
);

use constant INVALID_BUG_ID    => -1;
use constant INVALID_BUG_ALIAS => 'aaaaaaa12345';
use constant PRIVATE_BUG_USER  => 'QA_Selenium_TEST';

use constant CREATE_BUG => {
  'priority'    => 'Highest',
  'status'      => 'CONFIRMED',
  'version'     => 'unspecified',
  'creator'     => 'editbugs',
  'description' => '-- Comment Created By Bugzilla XML-RPC Tests --',
  'cc'          => ['unprivileged'],
  'component'   => 'c1',
  'platform'    => 'PC',

  # It's necessary to assign the bug to somebody who isn't in the
  # timetracking group, for the Bug.update tests.
  'assigned_to'    => PRIVATE_BUG_USER,
  'summary'        => 'WebService Test Bug',
  'product'        => 'Another Product',
  'op_sys'         => 'Linux',
  'severity'       => 'normal',
  'qa_contact'     => 'canconfirm',
  version          => 'Another1',
  url              => 'http://www.bugzilla.org/',
  target_milestone => 'AnotherMS1',
};

sub create_bug_fields {
  my ($config) = @_;
  my %bug = %{CREATE_BUG()};
  foreach my $field (qw(creator assigned_to qa_contact)) {
    my $value = $bug{$field};
    $bug{$field} = $config->{"${value}_user_login"};
  }
  $bug{cc} = [map { $config->{$_ . "_user_login"} } @{$bug{cc}}];
  return \%bug;
}

sub bug_tests {
  my ($public_id, $private_id) = @_;
  return [
    {
      args  => {ids => [$private_id]},
      error => "You are not authorized to access",
      test  => 'Logged-out user cannot access a private bug',
    },
    {
      args => {ids => [$public_id]},
      test => 'Logged-out user can access a public bug.',
    },
    {
      args  => {ids => [INVALID_BUG_ID]},
      error => "not a valid bug number",
      test  => 'Passing invalid bug id returns error "Invalid Bug ID"',
    },
    {
      args  => {ids => [undef]},
      error => "You must enter a valid bug number",
      test  => 'Passing undef as bug id param returns error "Invalid Bug ID"',
    },
    {
      args  => {ids => [INVALID_BUG_ALIAS]},
      error => "nor an alias to a bug",
      test  => 'Passing invalid bug alias returns error "Invalid Bug Alias"',
    },

    {
      user  => 'editbugs',
      args  => {ids => [$private_id]},
      error => "You are not authorized to access",
      test  => 'Access to a private bug is denied to a user without privs',
    },
    {
      user => 'unprivileged',
      args => {ids => [$public_id]},
      test => 'User without privs can access a public bug',
    },
    {
      user => 'admin',
      args => {ids => [$public_id]},
      test => 'Admin can access a public bug.',
    },
    {
      user => PRIVATE_BUG_USER,
      args => {ids => [$private_id]},
      test => 'User with privs can successfully access a private bug',
    },

    # This helps webservice_bug_attachment get private attachment ids
    # from the public bug, and doesn't hurt for the other tests.
    {
      user => PRIVATE_BUG_USER,
      args => {ids => [$public_id]},
      test => 'User with privs can also access the public bug',
    },
  ];
}

use constant STANDARD_BUG_TESTS => bug_tests('public_bug', 'private_bug');

1;
