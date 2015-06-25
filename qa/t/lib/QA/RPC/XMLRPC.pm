# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# -*- Mode: perl; indent-tabs-mode: nil -*-

package QA::RPC::XMLRPC;
use strict;
use base qw(QA::RPC XMLRPC::Lite);

use constant TYPE => 'XML-RPC';
use constant DATETIME_REGEX => qr/^\d{8}T\d\d:\d\d:\d\d$/;

1;

__END__
