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
# The Original Code is the BMO Bugzilla Extension.
#
# The Initial Developer of the Original Code is the Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2007
# the Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   David Lawrence <dkl@mozilla.com>

package Bugzilla::Extension::BMO::Constants;
use strict;
use base qw(Exporter);
our @EXPORT = qw(
    REQUEST_MAX_ATTACH_LINES
    DEV_ENGAGE_DISCUSS_NEEDINFO
);

# Maximum attachment size in lines that will be sent with a 
# requested attachment flag notification.
use constant REQUEST_MAX_ATTACH_LINES => 1000;

# Requestees who need a needinfo flag set for the dev engagement
# discussion bug
use constant DEV_ENGAGE_DISCUSS_NEEDINFO => qw(
    afabbro@mozilla.com
    dcamp@mozilla.com
    jswisher@mozilla.com
    rchau@mozilla.com
    stormy@mozilla.com
    spersing@mozilla.com
);

1;
