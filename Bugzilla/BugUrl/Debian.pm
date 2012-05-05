# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::BugUrl::Debian;
use strict;
use base qw(Bugzilla::BugUrl);

use Bugzilla::Error;
use Bugzilla::Util;

###############################
####        Methods        ####
###############################

sub should_handle {
    my ($class, $uri) = @_;
    return ($uri->authority =~ /^bugs.debian.org$/i) ? 1 : 0;
}

sub _check_value {
    my $class = shift;

    my $uri = $class->SUPER::_check_value(@_);

    # Debian BTS URLs can look like various things:
    #   http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1234
    #   http://bugs.debian.org/1234
    my $bug_id;
    if ($uri->path =~ m|^/(\d+)$|) {
        $bug_id = $1;
    }
    elsif ($uri->path =~ /bugreport\.cgi$/) {
        $bug_id = $uri->query_param('bug');
        detaint_natural($bug_id);
    }
    if (!$bug_id) {
        ThrowUserError('bug_url_invalid',
                       { url => $uri->path, reason => 'id' });
    }
    # This is the shortest standard URL form for Debian BTS URLs,
    # and so we reduce all URLs to this.
    return new URI("http://bugs.debian.org/" . $bug_id);
}

1;
