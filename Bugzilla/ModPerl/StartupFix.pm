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

# This module is a source filter that removes every subsequent line
# if this is the first time apache has started,
# as reported by Apache2::ServerUtil::restart_count(), which is 1
# on the first start.

my $FIRST_STARTUP = <<'CODE';
warn "Bugzilla::ModPerl::StartupFix: Skipping first startup using source filter\n";
1;
CODE

sub import {
    my ($class) = @_;
    my ($ref)  = {};
    filter_add( bless $ref, $class );
}

# this will be called for each line.
# For the first line replaced, we insert $FIRST_STARTUP.
# Every subsequent line is replaced with an empty string.
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