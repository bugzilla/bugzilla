# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Test::MockParams;
use 5.10.1;
use strict;
use warnings;
use Try::Tiny;
use Capture::Tiny qw(capture_merged);
use Test2::Tools::Mock qw(mock);

use Bugzilla::Config;
use Safe;

our $Params;

BEGIN {
  our $Mock = mock 'Bugzilla::Config' => (
    override => [
      'read_param_file' => sub {
        my ($class) = @_;
        return {} unless $Params;
        my $s = Safe->new;
        $s->reval($Params);
        die "Error evaluating params: $@" if $@;
        return {%{$s->varglob('param')}};
      },
      '_write_file' => sub {
        my ($class, $str) = @_;
        $Params = $str;
      },
    ],
  );
}

sub import {
  my ($self, %answers) = @_;
  state $first_time = 0;

  require Bugzilla::Field;
  require Bugzilla::Status;
  require Bugzilla;
  my $Bugzilla = mock 'Bugzilla' =>
    (override => [installation_answers => sub { \%answers },],);
  my $BugzillaField = mock 'Bugzilla::Field' =>
    (override => [get_legal_field_values => sub { [] },],);
  my $BugzillaStatus = mock 'Bugzilla::Status' =>
    (override => [closed_bug_statuses => sub { die "no database" },],);

  # prod-like defaults
  $answers{user_info_class}   //= 'GitHubAuth,CGI';
  $answers{user_verify_class} //= 'GitHubAuth,DB';

  if ($first_time++) {
    capture_merged {
      Bugzilla::Config::update_params();
    };
  }
  else {
    Bugzilla::Config::SetParam($_, $answers{$_}) for keys %answers;
  }
}

1;
