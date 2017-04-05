#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Update;
use Digest::MD5 qw(md5_hex);
use List::MoreUtils qw(any);

# Check whether or not the user is logged in
my $user = Bugzilla->login(LOGIN_OPTIONAL);
my $cgi = Bugzilla->cgi;
my $vars = {};

# Yes, I really want to avoid two calls to the id method.
my $user_id = $user->id;

# We only cache unauthenticated requests now, because invalidating is harder for logged in users.
my $can_cache = $user_id == 0;

# And log out the user if requested. We do this first so that nothing
# else accidentally relies on the current login.
if ($cgi->param('logout')) {
    Bugzilla->logout();
    $user = Bugzilla->user;
    $user_id = 0;
    $can_cache = 0;
    $vars->{'message'} = "logged_out";
    # Make sure that templates or other code doesn't get confused about this.
    $cgi->delete('logout');
}

# our weak etag is based on the bugzilla version parameter (BMO customization) and the announcehtml
# if either change, the cache will be considered invalid.
my @etag_parts = (
    Bugzilla->params->{bugzilla_version},
    Bugzilla->params->{announcehtml},
    Bugzilla->params->{createemailregexp},
);
my $weak_etag = q{W/"} . md5_hex(@etag_parts) . q{"};
my $if_none_match = $cgi->http('If-None-Match');

# load balancer (or client) will check back with us after max-age seconds
# If the etag in If-None-Match is unchanged, we quickly respond without doing much work.
my @cache_control = (
    $can_cache ? 'public' : 'no-cache',
    sprintf('max-age=%d', 60 * 5),
);

if ($can_cache && $if_none_match && any { $_ eq $weak_etag } split(/,\s*/, $if_none_match)) {
    print $cgi->header(-status => '304 Not Modified', -ETag => $weak_etag);
}
else {
    my $template = Bugzilla->template;
    $cgi->content_security_policy(script_src  => ['self']);

    # Return the appropriate HTTP response headers.
    print $cgi->header(
        -Cache_Control => join(', ', @cache_control),
        $can_cache ? (-ETag => $weak_etag) : (),
    );

    if ($user_id && $user->in_group('admin')) {
        # If 'urlbase' is not set, display the Welcome page.
        unless (Bugzilla->params->{'urlbase'}) {
            $template->process('welcome-admin.html.tmpl')
                or ThrowTemplateError($template->error());
            exit;
        }
        # Inform the administrator about new releases, if any.
        $vars->{'release'} = Bugzilla::Update::get_notifications();
    }

    $vars->{use_login_page} = 1;

    # Generate and return the UI (HTML page) from the appropriate template.
    $template->process("index.html.tmpl", $vars)
        or ThrowTemplateError( $template->error() );
}
