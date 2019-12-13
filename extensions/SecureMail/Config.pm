# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla SecureMail Extension
#
# The Initial Developer of the Original Code is Mozilla.
# Portions created by Mozilla are Copyright (C) 2008 Mozilla Corporation.
# All Rights Reserved.
#
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Gervase Markham <gerv@gerv.net>

package Bugzilla::Extension::SecureMail;

use 5.10.1;
use strict;
use warnings;

use constant NAME => 'SecureMail';

use constant REQUIRED_MODULES => [
  {package => 'Crypt-OpenPGP', module => 'Crypt::OpenPGP', version => '1.12',},
  {package => 'Crypt-SMIME',   module => 'Crypt::SMIME',   version => 0,},
  {package => 'HTML-Tree',     module => 'HTML::Tree',     version => 0,},
  {
    package => 'Bytes-Random-Secure',
    module  => 'Bytes::Random::Secure',
    version => 0
  }
];

__PACKAGE__->NAME;
