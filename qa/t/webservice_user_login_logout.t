# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

##########################################################
# Test for xmlrpc call to User.login() and User.logout() #
##########################################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Data::Dumper;
use QA::Util;
use Test::More tests => 119;
my ($config, @clients) = get_rpc_clients();

use constant INVALID_EMAIL => '@invalid_user@';

my $user = $config->{unprivileged_user_login};
my $pass = $config->{unprivileged_user_passwd};
my $error = "The username or password you entered is not valid";

my @tests = (
    { user => 'unprivileged',
      test => "Unprivileged user can log in successfully",
    },

    { args  => { login => $user, password => '' },
      error => $error,
      test  => "Empty password can't log in",
    },
    { args  => { login => '', password => $pass },
      error => $error,
      test  => "Empty login can't log in",
    },
    { args  => { login => $user },
      error => "requires a password argument",
      test  => "Undef password can't log in",
    },
    { args  => { password => $pass },
      error => "requires a login argument",
      test  => "Undef login can't log in",
    },

    { args  => { login => INVALID_EMAIL, password => $pass },
      error => $error,
      test  => "Invalid email can't log in",
    },
    { args  => { login => $user, password => '*' },
      error => $error,
      test  => "Invalid password can't log in",
    },

    { args  => { login    => $config->{disabled_user_login},
                 password => $config->{disabled_user_passwd} },
      error => "!!This is the text!!",
      test  => "Can't log in with a disabled account",
    },
    { args  => { login => $config->{disabled_user_login}, password => '*' },
      error => $error,
      test  => "Logging in with invalid password doesn't show disabledtext",
    },
);

sub _login_args {
    my $args = shift;
    my %fixed_args = %$args;
    $fixed_args{Bugzilla_login} = delete $fixed_args{login};
    $fixed_args{Bugzilla_password} = delete $fixed_args{password};
    return \%fixed_args;
}

foreach my $rpc (@clients) {
    if ($rpc->bz_get_mode) {
        $rpc->bz_call_fail('User.logout', undef, 'must use HTTP POST',
                           'User.logout fails when called via GET');
    }

    foreach my $t (@tests) {
        if ($t->{user}) {
            my $username = $config->{$t->{user} . '_user_login'};
            my $password = $config->{$t->{user} . '_user_passwd'};

            if ($rpc->bz_get_mode) {
                $rpc->bz_call_fail('User.login',
                    { login => $username, password => $password },
                    'must use HTTP POST', $t->{test} . ' (fails on GET)');
            }
            else {
                $rpc->bz_log_in($t->{user});
                ok($rpc->{_bz_credentials}->{token}, 'Login token returned');
                $rpc->bz_call_success('User.logout');
            }

            if ($t->{error}) {
                $rpc->bz_call_fail('Bugzilla.version',
                    { Bugzilla_login => $username,
                      Bugzilla_password => $password });
            }
            else {
                $rpc->bz_call_success('Bugzilla.version',
                    { Bugzilla_login => $username,
                      Bugzilla_password => $password });
            }
        }
        else {
            # Under GET, there's no reason to have extra failing tests.
            if (!$rpc->bz_get_mode) {
                $rpc->bz_call_fail('User.login', $t->{args}, $t->{error},
                                   $t->{test});
            }
            if (defined $t->{args}->{login}
                and defined $t->{args}->{password})
            {
                my $fixed_args = _login_args($t->{args});
                $rpc->bz_call_fail('Bugzilla.version', $fixed_args,
                    $t->{error}, "Bugzilla_login: " . $t->{test});
            }
        }
    }
}
