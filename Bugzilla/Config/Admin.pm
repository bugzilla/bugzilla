# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::Admin;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;
use JSON::XS qw(decode_json encode_json);
use List::MoreUtils qw(all);
use Scalar::Util qw(looks_like_number);

our $sortkey = 200;

sub get_param_list {
  my $class      = shift;
  my @param_list = (
    {name => 'allowbugdeletion', type => 'b', default => 0},

    {name => 'allowemailchange', type => 'b', default => 1},

    {name => 'allowuserdeletion', type => 'b', default => 0},

    {
      name    => 'last_visit_keep_days',
      type    => 't',
      default => 10,
      checker => \&check_numeric
    },

    {name => 'rate_limit_active', type => 'b', default => 1,},

    {
      name    => 'rate_limit_rules',
      type    => 'l',
      default => '{"get_bug": [75, 60], "show_bug": [75, 60], "github": [10, 60]}',
      checker => \&check_rate_limit_rules,
      updater => \&update_rate_limit_rules,
    },

    {name => 'log_user_requests', type => 'b', default => 0,}
  );
  return @param_list;
}

sub check_rate_limit_rules {
  my $rules = shift;

  my $val = eval { decode_json($rules) };
  return "failed to parse json" unless defined $val;
  return "value is not HASH"    unless ref $val && ref($val) eq 'HASH';
  return "rules are invalid"    unless all {
    ref($_) eq 'ARRAY' && looks_like_number($_->[0]) && looks_like_number($_->[1])
  }
  values %$val;

  foreach my $required (qw( show_bug get_bug github )) {
    return "missing $required" unless exists $val->{$required};
  }

  return "";
}

sub update_rate_limit_rules {
  my ($rules) = @_;
  my $val = decode_json($rules);
  $val->{github} = [10, 60];
  return encode_json($val);
}

1;
