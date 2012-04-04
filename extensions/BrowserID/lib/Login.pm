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
    
    # XXX Add 120 secs because 'expires' is currently broken in deployed 
    # BrowserID server - it returns exact current time, so is immediately
    # expired! This should be fixed soon.
    if ($info->{'status'} eq "okay" &&
        $info->{'audience'} eq $audience &&
        (($info->{'expires'} / 1000) + 120) > time())
    {
        my $login_data = {
            'username' => $info->{'email'}
        };

        my $result = 
                    Bugzilla::Auth::Verify->create_or_update_user($login_data);
        return $result if $result->{'failure'};
        
        my $user = $result->{'user'};
        
        # BrowserID logins are currently restricted to less powerful accounts -
        # the most you can have is 'editbugs'. This is while the technology 
        # is maturing. So we need to check that the user doesn't have 'too 
        # many permissions' to log in this way. 
        #
        # If a newly-created account has too many permissions, this code will
        # create an account for them and then fail their login. Which isn't
        # great, but they can still use normal-Bugzilla-login password 
        # recovery.
        my @safe_groups = ('everyone', 'canconfirm', 'editbugs');        
        foreach my $group (@{ $user->groups() }) {
            if (!grep { $group->name eq $_ } @safe_groups) {
                return { failure => AUTH_LOGINFAILED };
            }
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
