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
# The Original Code is the FlagTypeComment Bugzilla Extension.
#
# The Initial Developer of the Original Code is Alex Keybl 
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Alex Keybl <akeybl@mozilla.com>
#   byron jones <glob@mozilla.com>

package Bugzilla::Extension::FlagTypeComment::Constants;
use strict;

use base qw(Exporter);
our @EXPORT = qw(
    FLAGTYPE_COMMENT_TEMPLATES
    FLAGTYPE_COMMENT_STATES
    FLAGTYPE_COMMENT_BUG_FLAGS
    FLAGTYPE_COMMENT_ATTACHMENT_FLAGS
);

use constant FLAGTYPE_COMMENT_STATES => ("?", "+", "-");
use constant FLAGTYPE_COMMENT_BUG_FLAGS => 0;
use constant FLAGTYPE_COMMENT_ATTACHMENT_FLAGS => 1;

sub FLAGTYPE_COMMENT_TEMPLATES {
    my @result = ("admin/flag-type/edit.html.tmpl");
    if (FLAGTYPE_COMMENT_BUG_FLAGS) {
        push @result, ("bug/comments.html.tmpl");
    }
    if (FLAGTYPE_COMMENT_ATTACHMENT_FLAGS) {
        push @result, (
            "attachment/edit.html.tmpl",
            "attachment/createformcontents.html.tmpl",
        );
    }
    return @result;
}

1;
