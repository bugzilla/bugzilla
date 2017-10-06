# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::ModPerl::StartupFix;
use 5.10.1;
use strict;
use warnings;

use Filter::Util::Call;
use Apache2::ServerUtil ();

my $FIRST_STARTUP = <<'CODE';
warn "Bugzilla::ModPerl::StartupFix: Skipping first startup using source filter\n";
1;
CODE

sub import {
    my ($type) = @_;
    my ($ref)  = {};
    filter_add( bless $ref );
}

sub filter {
    my ($self) = @_;
    my ($status);
    if ($status = filter_read() > 0) {
        if (Apache2::ServerUtil::restart_count() < 2) {
            if (!$self->{did_it}) {
                $self->{did_it} = 1;
                $_ = $FIRST_STARTUP;
            }
            else {
                $_ = "";
            }
        }
    }
    return $status;
}

1;