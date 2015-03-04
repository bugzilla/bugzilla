# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::GitHubAuth::Util;

use strict;
use warnings;

use Bugzilla::Util qw(correct_urlbase);
use URI;

use base qw(Exporter);
our @EXPORT = qw( target_uri );


# this is like correct_urlbase() except it returns the *requested* uri, before http url rewrites have been applied.
# needed to generate github's redirect_uri.
sub target_uri {
    my $cgi = Bugzilla->cgi;
    my $base = URI->new(correct_urlbase());
    if (my $request_uri = $cgi->request_uri) {
        $base->path('');
        $request_uri =~ s!^/+!!;
        return URI->new($base . "/" . $request_uri);
    }
    else {
        return URI->new(correct_urlbase() . $cgi->url(-relative => 1, query => ));
    }
}

1;
