# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the BrowserID Bugzilla Extension.
#
# The Initial Developer of the Original Code is the Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Gervase Markham <gerv@gerv.net>

package Bugzilla::Extension::BrowserID::Login;
use strict;
use base qw(Bugzilla::Auth::Login);

use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Token;

use JSON;
use LWP::UserAgent;

use constant requires_verification => 0;
use constant is_automatic          => 1;

sub get_login_info {
    my ($self) = @_;

    my $cgi = Bugzilla->cgi;

    my $assertion = $cgi->param("browserid_assertion");
    # Avoid the assertion being copied into any 'echoes' of the current URL
    # in the page.
    $cgi->delete('browserid_assertion');
    
    if (!$assertion) {
        return { failure => AUTH_NODATA };
    }
    
    my $token = $cgi->param("token");
    $cgi->delete('token');
    check_hash_token($token, ['login']);
        
    my $urlbase = new URI(correct_urlbase());
    my $audience = $urlbase->scheme . "://" . $urlbase->host_port;
    
    my $ua = new LWP::UserAgent();
    
    my $info = { 'status' => 'browserid-server-broken' };
    eval {
        my $response = $ua->post("https://browserid.org/verify",
                                 [assertion => $assertion, 
                                  audience  => $audience]);

        $info = decode_json($response->content());
    };
    
    if ($info->{'status'} eq "okay" &&
        $info->{'audience'} eq $audience &&
        ($info->{'expires'} / 1000) > time())
    {
        my $login_data = {
            'username' => $info->{'email'}
        };

        my $result = 
                    Bugzilla::Auth::Verify->create_or_update_user($login_data);
        return $result if $result->{'failure'};
        
        my $user = $result->{'user'};
        
        # You can restrict people in a particular group from logging in using
        # BrowserID by making that group a member of a group called
        # "no-browser-id".
        #
        # If you have your "createemailregexp" set up in such a way that a
        # newly-created account is a member of "no-browser-id", this code will
        # create an account for them and then fail their login. Which isn't
        # great, but they can still use normal-Bugzilla-login password 
        # recovery.
        if ($user->in_group('no-browser-id')) {
            # We use a custom error here, for greater clarity, rather than
            # returning a failure code.
            ThrowUserError('browserid_account_too_powerful');
        }
    
        $login_data->{'user'} = $user;
        $login_data->{'user_id'} = $user->id;
        
        return $login_data;
    }
    else {
        return { failure => AUTH_LOGINFAILED };
    }
}

# Pinched from Bugzilla::Auth::Login::CGI
sub fail_nodata {
    my ($self) = @_;
    my $cgi = Bugzilla->cgi;
    my $template = Bugzilla->template;

    if (Bugzilla->usage_mode != USAGE_MODE_BROWSER) {
        ThrowUserError('login_required');
    }

    print $cgi->header();
    $template->process("account/auth/login.html.tmpl",
                       { 'target' => $cgi->url(-relative=>1) }) 
        || ThrowTemplateError($template->error());
    exit;
}

1;
