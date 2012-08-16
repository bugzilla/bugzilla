# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::PatchReader::CVSClient;

use strict;

sub parse_cvsroot {
    my $cvsroot = $_[0];
    # Format: :method:[user[:password]@]server[:[port]]/path
    if ($cvsroot =~ /^:([^:]*):(.*?)(\/.*)$/) {
        my %retval;
        $retval{protocol} = $1;
        $retval{rootdir} = $3;
        my $remote = $2;
        if ($remote =~ /^(([^\@:]*)(:([^\@]*))?\@)?([^:]*)(:(.*))?$/) {
            $retval{user} = $2;
            $retval{password} = $4;
            $retval{server} = $5;
            $retval{port} = $7;
            return %retval;
        }
    }

    return (
        rootdir => $cvsroot
    );
}

sub cvs_co {
    my ($cvsroot, @files) = @_;
    my $cvs = $::cvsbin || "cvs";
    return system($cvs, "-Q", "-d$cvsroot", "co", @files);
}

sub cvs_co_rev {
    my ($cvsroot, $rev, @files) = @_;
    my $cvs = $::cvsbin || "cvs";
    return system($cvs, "-Q", "-d$cvsroot", "co", "-r$rev", @files);
}

1
