# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use 5.10.1;
use Test::More tests => 1;

use Crypt::OpenPGP;

my $pubring = new Crypt::OpenPGP::KeyRing(Data => PUBLIC_KEY());
my $pgp = new Crypt::OpenPGP(PubRing => $pubring);
{
    local $SIG{ALRM} = sub { fail("stuck in a loop"); exit; };
    alarm(5);
    my $encrypted = $pgp->encrypt(
        Data       => "hello, world",
        Recipients => "@",
        Cipher     => 'CAST5',
        Armour     => 0
    );
    alarm(0);
}
pass("didn't get stuck in a loop");

sub PUBLIC_KEY {
    return <<'KEY';
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.9 (GNU/Linux)

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
=skQe
-----END PGP PUBLIC KEY BLOCK-----
KEY
}


