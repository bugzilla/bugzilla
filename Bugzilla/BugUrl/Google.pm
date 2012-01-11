# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::Google;
use strict;
use base qw(Bugzilla::BugUrl);

use Bugzilla::Error;
use Bugzilla::Util;

###############################
####        Methods        ####
###############################

sub should_handle {
    my ($class, $uri) = @_;
    return ($uri->authority =~ /^code.google.com$/i) ? 1 : 0;
}

sub _check_value {
    my ($class, $uri) = @_;
    
    $uri = $class->SUPER::_check_value($uri);

    my $value = $uri->as_string;
    # Google Code URLs only have one form:
    #   http(s)://code.google.com/p/PROJECT_NAME/issues/detail?id=1234
    my $project_name;
    if ($uri->path =~ m|^/p/([^/]+)/issues/detail$|) {
        $project_name = $1;
    } else {
        ThrowUserError('bug_url_invalid', { url => $value });
    }
    my $bug_id = $uri->query_param('id');
    detaint_natural($bug_id);
    if (!$bug_id) {
        ThrowUserError('bug_url_invalid', { url => $value, reason => 'id' });
    }
    # While Google Code URLs can be either HTTP or HTTPS,
    # always go with the HTTP scheme, as that's the default.
    $value = "http://code.google.com/p/" . $project_name .
             "/issues/detail?id=" . $bug_id;

    return new URI($value);
}

1;
