# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# -*- Mode: perl; indent-tabs-mode: nil -*-

package QA::RPC;
use strict;
use Data::Dumper;
use QA::Util;
use QA::Tests qw(PRIVATE_BUG_USER create_bug_fields);
use Storable qw(dclone);
use Test::More;

sub bz_config {
    my $self = shift;
    $self->{bz_config} ||= QA::Util::get_config();
    return $self->{bz_config};
}

# True if we're doing calls over GET instead of POST.
sub bz_get_mode { return 0 }

# When doing bz_log_in over GET, we can't actually call User.login,
# we just store credentials here and then pass them as Bugzilla_login
# and Bugzilla_password with every future call until User.logout is called
# (which actually just calls _bz_clear_credentials, under GET).
sub _bz_credentials {
    my ($self, $user, $pass) = @_;
    if (@_ == 3) {
        $self->{_bz_credentials}->{user} = $user;
        $self->{_bz_credentials}->{pass} = $pass;
    }
    return $self->{_bz_credentials};
}
sub _bz_clear_credentials { delete $_[0]->{_bz_credentials} }

################################
# Helpers for RPC test scripts #
################################

sub bz_log_in {
    my ($self, $user) = @_;
    my $username = $self->bz_config->{"${user}_user_login"};
    my $password = $self->bz_config->{"${user}_user_passwd"};

    if ($self->bz_get_mode) {
        $self->_bz_credentials($username, $password);
        return;
    }

    my $call = $self->bz_call_success(
        'User.login', { login => $username, password => $password });
    cmp_ok($call->result->{id}, 'gt', 0, $self->TYPE . ": Logged in as $user");
    $self->{_bz_credentials}->{token} = $call->result->{token};
}

sub bz_call_success {
    my ($self, $method, $orig_args, $test_name) = @_;
    my $args = $orig_args ? dclone($orig_args) : {};

    if ($self->bz_get_mode and $method eq 'User.logout') {
        $self->_bz_clear_credentials();
        return;
    }

    my $call;
    # Under XMLRPC::Lite, if we pass undef as the second argument,
    # it sends a single param <value />, which shows up as an
    # empty string on the Bugzilla side.
    if ($self->{_bz_credentials}->{token}) {
        $args->{Bugzilla_token} = $self->{_bz_credentials}->{token};
    }

    if (scalar keys %$args) {
        $call = $self->call($method, $args);
    }
    else {
        $call = $self->call($method);
    }
    $test_name ||= "$method returned successfully";
    $self->_handle_undef_response($test_name) if !$call;
    ok(!$call->fault, $self->TYPE . ": $test_name")
        or diag($call->faultstring);

    if ($method eq 'User.logout') {
        delete $self->{_bz_credentials}->{token};
    }
    return $call;
}

sub bz_call_fail {
    my ($self, $method, $orig_args, $faultstring, $test_name) = @_;
    my $args = $orig_args ? dclone($orig_args) : {};

    if ($self->{_bz_credentials}->{token}) {
        $args->{Bugzilla_token} = $self->{_bz_credentials}->{token};
    }

    $test_name ||= "$method failed (as intended)";
    my $call = $self->call($method, $args);
    $self->_handle_undef_response($test_name) if !$call;
    ok($call->fault, $self->TYPE . ": $test_name")
        or diag("Returned: " . Dumper($call->result));
    if (defined $faultstring) {
        cmp_ok(trim($call->faultstring), '=~', $faultstring,
               $self->TYPE . ": Got correct fault for $method");
    }
    ok($call->faultcode
       && (($call->faultcode < 32000 && $call->faultcode > -32000)
           # Fault codes 32610 and above are OK because they are errors
           # that we expect and test for sometimes.
           || $call->faultcode >= 32610),
       $self->TYPE . ': Fault code is set properly')
        or diag("Code: " . $call->faultcode
                . " Message: " . $call->faultstring);

    return $call;
}

sub _handle_undef_response {
    my ($self, $test_name) = @_;
    my $response = $self->transport->http_response;
    die "$test_name:\n", $response->as_string;
}

sub bz_get_products {
    my ($self) = @_;
    $self->bz_log_in('QA_Selenium_TEST');

    my $accessible = $self->bz_call_success('Product.get_accessible_products');
    my $prod_call = $self->bz_call_success('Product.get', $accessible->result);
    my %products;
    foreach my $prod (@{ $prod_call->result->{products} }) {
        $products{$prod->{name}} = $prod->{id};
    }

    $self->bz_call_success('User.logout');
    return \%products;
}

sub _string_array { map { random_string() } (1..$_[0]) }

sub bz_create_test_bugs {
    my ($self, $second_private) = @_;
    my $config = $self->bz_config;

    my @whiteboard_strings = _string_array(3);
    my @summary_strings = _string_array(3);

    my $public_bug = create_bug_fields($config);
    $public_bug->{alias} = random_string(40);
    $public_bug->{whiteboard} = join(' ', @whiteboard_strings);
    $public_bug->{summary} = join(' ', @summary_strings);

    my $private_bug = dclone($public_bug);
    $private_bug->{alias} = random_string(40);
    if ($second_private) {
        $private_bug->{product}   = 'QA-Selenium-TEST';
        $private_bug->{component} = 'QA-Selenium-TEST';
        $private_bug->{target_milestone} = 'QAMilestone';
        $private_bug->{version} = 'QAVersion';
        # Although we don't directly use this, this helps some tests that
        # depend on the values in $private_bug.
        $private_bug->{creator} = $config->{PRIVATE_BUG_USER . '_user_login'};
    }

    my @create_bugs = (
        { user => 'editbugs',
          args => $public_bug,
          test => 'Create a public bug' },
        { user => $second_private ? PRIVATE_BUG_USER : 'editbugs',
          args => $private_bug,
          test => $second_private ? 'Create a private bug'
                                  : 'Create a second public bug' },
    );

    my $post_success = sub {
        my ($call, $t) = @_;
        my $id = $call->result->{id};
        $t->{args}->{id} = $id;
    };

    # Creating the bugs isn't really a test, it's just preliminary work
    # for the tests. So we just run it with one of the RPC clients.
    $self->bz_run_tests(tests => \@create_bugs, method => 'Bug.create',
                        post_success => $post_success);

    return ($public_bug, $private_bug);
}

sub bz_run_tests {
    my ($self, %params) = @_;
    # Required params
    my $config = $self->bz_config;
    my $tests  = $params{tests};
    my $method = $params{method};

    # Optional params
    my $post_success = $params{post_success};
    my $pre_call = $params{pre_call};

    my $former_user = '';
    foreach my $t (@$tests) {
        # Only logout/login if the user has changed since the last test
        # (this saves us LOTS of needless logins).
        my $user = $t->{user} || '';
        if ($former_user ne $user) {
            $self->bz_call_success('User.logout') if $former_user;
            $self->bz_log_in($user) if $user;
            $former_user = $user;
        }

        $pre_call->($t, $self) if $pre_call;

        if ($t->{error}) {
            $self->bz_call_fail($method, $t->{args}, $t->{error}, $t->{test});
        }
        else {
            my $call = $self->bz_call_success($method, $t->{args}, $t->{test});
            if ($call->result && $post_success) {
                $post_success->($call, $t, $self);
            }
        }
    }

    $self->bz_call_success('User.logout') if $former_user;
}

sub bz_test_bug {
    my ($self, $fields, $bug, $expect, $t, $creation_time) = @_;

    foreach my $field (sort @$fields) {
        # "description" is used by Bug.create but comments are not returned
        # by Bug.get or Bug.search.
        next if $field eq 'description';

        my @include = @{ $t->{args}->{include_fields} || [] };
        my @exclude = @{ $t->{args}->{exclude_fields} || [] };
        if ( (@include and !grep($_ eq $field, @include))
             or (@exclude and grep($_ eq $field, @exclude)) )
        {
            ok(!exists $bug->{$field}, "$field is not included")
              or diag Dumper($bug);
            next;
        }

        if ($field =~ /^is_/) {
            ok(defined $bug->{$field}, $self->TYPE . ": $field is not null");
            is($bug->{$field} ? 1 : 0, $expect->{$field} ? 1 : 0,
               $self->TYPE . ": $field has the right boolean value");
        }
        elsif ($field eq 'cc') {
            foreach my $cc_item (@{ $expect->{cc} || [] }) {
                ok(grep($_ eq $cc_item, @{ $bug->{cc} }),
                   $self->TYPE . ": $field contains $cc_item");
            }
        }
        elsif ($field eq 'creation_time' or $field eq 'last_change_time') {
            my $creation_day;
            # XML-RPC and JSON-RPC have different date formats.
            if ($self->isa('QA::RPC::XMLRPC')) {
                $creation_day = $creation_time->ymd('');
            }
            else {
                $creation_day = $creation_time->ymd;
            }

            like($bug->{$field}, qr/^\Q${creation_day}\ET\d\d:\d\d:\d\d/,
                 $self->TYPE . ": $field has the right format");
        }
        else {
            is_deeply($bug->{$field}, $expect->{$field},
                      $self->TYPE . ": $field value is correct");
        }
    }
}

1;

__END__
