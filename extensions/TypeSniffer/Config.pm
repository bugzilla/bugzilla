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
# The Original Code is the TypeSniffer Bugzilla Extension.
#
# The Initial Developer of the Original Code is The Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Gervase Markham <gerv@mozilla.org>

package Bugzilla::Extension::TypeSniffer;
use strict;

use constant NAME => 'TypeSniffer';

use constant REQUIRED_MODULES => [
    {
        package => 'File-MimeInfo',
        module  => 'File::MimeInfo::Magic',
        version => '0'
    },
    {
        package => 'IO-stringy',
        module  => 'IO::Scalar',
        version => '0'
    },
];

__PACKAGE__->NAME;