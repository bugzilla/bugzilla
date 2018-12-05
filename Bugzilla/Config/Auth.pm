# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Config::Auth;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;
use Types::Standard qw(Tuple Maybe);
use Types::Common::Numeric qw(PositiveInt);

our $sortkey = 300;

sub get_param_list {
  my $class      = shift;
  my @param_list = (
    {name => 'auth_env_id', type => 't', default => '',},

    {name => 'auth_env_email', type => 't', default => '',},

    {name => 'auth_env_realname', type => 't', default => '',},

    # XXX in the future:
    #
    # user_verify_class and user_info_class should have choices gathered from
    # whatever sits in their respective directories
    #
    # rather than comma-separated lists, these two should eventually become
    # arrays, but that requires alterations to editparams first

    {
      name    => 'user_info_class',
      type    => 's',
      choices => ['CGI', 'Env', 'Env,CGI'],
      default => 'CGI',
      checker => \&check_multi
    },

    {
      name    => 'user_verify_class',
      type    => 'o',
      choices => ['DB', 'RADIUS', 'LDAP'],
      default => 'DB',
      checker => \&check_user_verify_class
    },

    {
      name    => 'rememberlogin',
      type    => 's',
      choices => ['on', 'defaulton', 'defaultoff', 'off'],
      default => 'on',
      checker => \&check_multi
    },

    {name => 'requirelogin', type => 'b', default => '0'},

    {name => 'webservice_email_filter', type => 'b', default => 0},

    {
      name    => 'emailregexp',
      type    => 't',
      default => q:^[\\w\\.\\+\\-=]+@[\\w\\.\\-]+\\.[\\w\\-]+$:,
      checker => \&check_regexp
    },

    {
      name    => 'emailregexpdesc',
      type    => 'l',
      default => 'A legal address must contain exactly one \'@\', and at least '
        . 'one \'.\' after the @.'
    },

    {name => 'emailsuffix', type => 't', default => ''},

    {
      name    => 'createemailregexp',
      type    => 't',
      default => q:.*:,
      checker => \&check_regexp
    },

    {
      name    => 'password_complexity',
      type    => 's',
      choices => ['no_constraints', 'bmo'],
      default => 'no_constraints',
      checker => \&check_multi
    },

    {name => 'password_check_on_login', type => 'b', default => '1'},

    {
      name    => 'passwdqc_min',
      type    => 't',
      default => 'undef, 24, 11, 8, 7',
      checker => \&_check_passwdqc_min,
    },

    {
      name    => 'passwdqc_max',
      type    => 't',
      default => '40',
      checker => \&_check_passwdqc_max,
    },

    {
      name    => 'passwdqc_passphrase_words',
      type    => 't',
      default => '3',
      checker => \&check_numeric,
    },

    {
      name    => 'passwdqc_match_length',
      type    => 't',
      default => '4',
      checker => \&check_numeric,
    },

    {
      name    => 'passwdqc_random_bits',
      type    => 't',
      default => '47',
      checker => \&_check_passwdqc_random_bits,
    },

    {
      name    => 'passwdqc_desc',
      type    => 'l',
      default => 'The password must be complex.',
    },

    {name => 'auth_delegation', type => 'b', default => 0,},

    {name => 'duo_host', type => 't', default => '',},
    {name => 'duo_akey', type => 't', default => '',},
    {name => 'duo_ikey', type => 't', default => '',},
    {name => 'duo_skey', type => 't', default => '',},

    {
      name    => 'mfa_group',
      type    => 's',
      choices => \&get_all_group_names,
      default => '',
      checker => \&check_group,
    },

    {
      name    => 'mfa_group_grace_period',
      type    => 't',
      default => '7',
      checker => \&check_numeric,
    }
  );
  return @param_list;
}

my $passwdqc_min = Tuple [
  Maybe [PositiveInt],
  Maybe [PositiveInt],
  Maybe [PositiveInt],
  Maybe [PositiveInt],
  Maybe [PositiveInt],
];

sub _check_passwdqc_min {
  my ($value) = @_;
  my @values = map { $_ eq 'undef' ? undef : $_ } split(/\s*,\s*/, $value);

  unless ($passwdqc_min->check(\@values)) {
    return "must be list of five values, that are either integers > 0 or undef";
  }

  my ($max, $max_pos);
  my $pos = 0;
  foreach my $value (@values) {
    if (defined $max && defined $value) {
      if ($value > $max) {
        return "Int$pos is larger than Int$max_pos ($max)";
      }
    }
    elsif (defined $value) {
      $max     = $value;
      $max_pos = $pos;
    }
    $pos++;
  }
  return "";
}

sub _check_passwdqc_max {
  my ($value) = @_;
  return "must be a positive integer" unless PositiveInt->check($value);
  return "must be greater than 8" unless $value > 8;
  return "";
}

sub _check_passwdqc_random_bits {
  my ($value) = @_;
  return "must be a positive integer" unless PositiveInt->check($value);
  return "must be between 24 and 85 inclusive"
    unless $value >= 24 && $value <= 85;
  return "";
}

1;
