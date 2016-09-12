# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::FlagDefaultRequestee::Constants;

use strict;

use base qw(Exporter);

our @EXPORT = qw(
    FLAGTYPE_TEMPLATES
);

use constant FLAGTYPE_TEMPLATES => (
    "attachment/edit.html.tmpl", 
    "attachment/createformcontents.html.tmpl", 
    "bug/edit.html.tmpl", 
    "bug/create/create.html.tmpl"
);

1;
