# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GitHubAuth::Login;
use strict;
use warnings;
use base qw(Bugzilla::Auth::Login);
use fields qw(github_failure);

use Scalar::Util qw(blessed);

use Bugzilla::Constants qw(AUTH_NODATA AUTH_ERROR USAGE_MODE_BROWSER );
use Bugzilla::Util qw(trick_taint correct_urlbase generate_random_password);
use Bugzilla::Extension::GitHubAuth::Client;
use Bugzilla::Extension::GitHubAuth::Client::Error ();
use Bugzilla::Extension::GitHubAuth::Util qw(target_uri);
use Bugzilla::Error;

use constant { requires_verification   => 1,
               is_automatic            => 1,
               user_can_create_account => 1 };

sub get_login_info {
    my ($self) = @_;
    my $cgi              = Bugzilla->cgi;
    my $github_login     = $cgi->param('github_login');
    my $github_email     = $cgi->param('github_email');
    my $github_email_key = $cgi->param('github_email_key');

    my $cookie = $cgi->cookie('Bugzilla_github_token');
    unless ($cookie) {
        my $token = generate_random_password();
        $cgi->send_cookie(-name     => 'Bugzilla_github_token',
                          -value    => $token,
                          Bugzilla->params->{'ssl_redirect'} ? ( -secure => 1 ) : (),
                          -httponly => 1);
        Bugzilla->request_cache->{github_token} = $token;
    }

    return { failure => AUTH_NODATA } unless $github_login;

    if ($github_email_key && $github_email) {
        trick_taint($github_email);
        trick_taint($github_email_key);
        return $self->_get_login_info_from_email($github_email, $github_email_key);
    }
    else {
       return $self->_get_login_info_from_github();
    }
}

sub _get_login_info_from_github {
    my ($self) = @_;
    my $cgi      = Bugzilla->cgi;
    my $template = Bugzilla->template;
    my $state    = $cgi->param('state');
    my $code     = $cgi->param('code');

    return { failure => AUTH_ERROR, error => 'github_missing_code' } unless $code;
    return { failure => AUTH_ERROR, error => 'github_invalid_state' } unless $state;

    trick_taint($code);
    trick_taint($state);

    my $target = target_uri();
    my $client = Bugzilla::Extension::GitHubAuth::Client->new;
    if ($state ne $client->get_state($target)) {
        return { failure => AUTH_ERROR, error => 'github_invalid_state' };
    }

    my ($access_token, $emails);
    eval {
        # The following variable lets us catch and return (rather than throw) errors
        # from our github client code, as required by the Auth API.
        local $Bugzilla::Extension::GitHubAuth::Client::Error::USE_EXCEPTION_OBJECTS = 1;
        $access_token = $client->get_access_token($code);
        $emails       = $client->get_user_emails($access_token);
    };
    my $e = $@;
    if (blessed $e && $e->isa('Bugzilla::Extension::GitHubAuth::Client::Error')) {
        my $key = $e->type eq 'user' ? 'user_error' : 'error';
        return { failure => AUTH_ERROR, $key => $e->error, details => $e->vars };
    }
    elsif ($e) {
        die $e;
    }

    my @emails = map { $_->{email} }
                 grep { $_->{verified} && $_->{email} !~ /\@users\.noreply\.github\.com$/ } @$emails;

    my $choose_email = sub {
        my ($email) = @_;
        my $uri  = $target->clone;
        my $key = Bugzilla::Extension::GitHubAuth::Client->get_email_key($email);
        $uri->query_param(github_email => $email);
        $uri->query_param(github_email_key => $key);
        return $uri;
    };

    my @bugzilla_users;
    my @github_emails;
    foreach my $email (@emails) {
        my $user = Bugzilla::User->new({name => $email, cache => 1});
        if ($user) {
            push @bugzilla_users, $user;
        }
        else {
            push @github_emails, $email;
        }
    }
    my @allowed_bugzilla_users = grep { not $_->in_group('no-github-auth') } @bugzilla_users;

    if (@allowed_bugzilla_users == 1) {
        my ($user) = @allowed_bugzilla_users;
        $cgi->remove_cookie('Bugzilla_github_token');
        return { username => $user->login, user_id => $user->id, github_auth => 1 };
    }
    elsif (@allowed_bugzilla_users > 1) {
        $self->{github_failure} = {
            template => 'account/auth/github-verify-account.html.tmpl',
            vars     => {
                bugzilla_users => \@allowed_bugzilla_users,
                choose_email   => $choose_email,
            },
        };
        return { failure => AUTH_NODATA };
    }
    elsif (@allowed_bugzilla_users == 0 && @bugzilla_users > 0 && @github_emails == 0) {
            return { failure    => AUTH_ERROR,
                     user_error => 'github_auth_account_too_powerful' };
    }
    elsif (@github_emails) {
        $self->{github_failure} = {
            template => 'account/auth/github-verify-account.html.tmpl',
            vars     => {
                github_emails => \@github_emails,
                choose_email  => $choose_email,
            },
        };
        return { failure => AUTH_NODATA };
    }
    else {
        return { failure => AUTH_ERROR, user_error => 'github_no_emails' };
    }
}

sub _get_login_info_from_email {
    my ($self, $github_email, $github_email_key) = @_;
    my $cgi = Bugzilla->cgi;

    my $key = Bugzilla::Extension::GitHubAuth::Client->get_email_key($github_email);
    unless ($github_email_key eq $key) {
        return { failure    => AUTH_ERROR,
                 user_error => 'github_invalid_email',
                 details    => { email => $github_email }};
    }

    my $user = Bugzilla::User->new({name => $github_email, cache => 1});
    return { failure    => AUTH_ERROR,
             user_error => 'github_auth_account_too_powerful' } if $user && $user->in_group('no-github-auth');

    $cgi->remove_cookie('Bugzilla_github_token');
    return { username => $github_email, github_auth => 1 };
}

sub fail_nodata {
    my ($self) = @_;
    my $cgi      = Bugzilla->cgi;
    my $template = Bugzilla->template;

    ThrowUserError('login_required') if Bugzilla->usage_mode != USAGE_MODE_BROWSER;

    my $file = $self->{github_failure}{template} // "account/auth/login.html.tmpl";
    my $vars = $self->{github_failure}{vars} // { target => $cgi->url(-relative=>1) };

    print $cgi->header();
    $template->process($file, $vars) or ThrowTemplateError($template->error());
    exit;
}


1;
