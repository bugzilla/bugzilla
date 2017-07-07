# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use lib qw( . lib local/lib/perl5 );
use Test::More tests => 2;

use Crypt::OpenPGP::Util;

{
    local $SIG{ALRM} = sub {
        fail("getting random bytes froze program");
        exit;
    };
    alarm(60);
    my $bytes = Crypt::OpenPGP::Util::get_random_bytes(32);
    alarm(0);
    pass("getting random bytes didn't freeze program");
    is(length $bytes, 32, "got 32 bytes");
}
