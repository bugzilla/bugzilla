# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push;

use strict;

use constant NAME => 'Push';

use constant REQUIRED_MODULES => [
    {
        package => 'Daemon-Generic',
        module  => 'Daemon::Generic',
        version => '0'
    },
    {
        package => 'JSON-XS',
        module  => 'JSON::XS',
        version => '2.0'
    },
    {
        package => 'Crypt-CBC',
        module  => 'Crypt::CBC',
        version => '0'
    },
    {
        package => 'Crypt-DES',
        module  => 'Crypt::DES',
        version => '0'
    },
    {
        package => 'Crypt-DES_EDE3',
        module  => 'Crypt::DES_EDE3',
        version => '0'
    },
];

use constant OPTIONAL_MODULES => [
    # connectors need the ability to extend this
    {
        package => 'Net-SFTP',
        module  => 'Net::SFTP',
        version => '0'
    },
    {
        package => 'XML-Simple',
        module  => 'XML::Simple',
        version => '0'
    },
];

__PACKAGE__->NAME;
