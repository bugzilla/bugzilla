# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TellUsMore::Constants;

use strict;
use base qw(Exporter);

our @EXPORT = qw(
    TELL_US_MORE_LOGIN

    MAX_ATTACHMENT_COUNT
    MAX_ATTACHMENT_SIZE

    MAX_REPORTS_PER_MINUTE

    TARGET_PRODUCT
    SECURITY_GROUP

    DEFAULT_VERSION
    DEFAULT_COMPONENT

    MANDATORY_BUG_FIELDS
    OPTIONAL_BUG_FIELDS

    MANDATORY_ATTACH_FIELDS
    OPTIONAL_ATTACH_FIELDS

    TOKEN_EXPIRY_DAYS

    VERSION_SOURCE_PRODUCTS
    VERSION_TARGET_PRODUCT

    RESULT_URL_SUCCESS
    RESULT_URL_FAILURE
);

use constant TELL_US_MORE_LOGIN => 'tellusmore@input.bugs';

use constant MAX_ATTACHMENT_COUNT => 2;
use constant MAX_ATTACHMENT_SIZE  => 512; # kilobytes

use constant MAX_REPORTS_PER_MINUTE => 2;

use constant TARGET_PRODUCT => 'Untriaged Bugs';
use constant SECURITY_GROUP => 'core-security';

use constant DEFAULT_VERSION => 'unspecified';
use constant DEFAULT_COMPONENT => 'General';

use constant MANDATORY_BUG_FIELDS => qw(
    creator
    description
    product
    summary
    user_agent
);

use constant OPTIONAL_BUG_FIELDS => qw(
    attachments
    creator_name
    restricted
    url
    version
);

use constant MANDATORY_ATTACH_FIELDS => qw(
    filename
    content_type
    content
);

use constant OPTIONAL_ATTACH_FIELDS => qw(
    description
);

use constant TOKEN_EXPIRY_DAYS => 7;

use constant VERSION_SOURCE_PRODUCTS => ('Firefox', 'Fennec');
use constant VERSION_TARGET_PRODUCT => 'Untriaged Bugs';

use constant RESULT_URL_SUCCESS => 'http://input.mozilla.org/bug/thanks/?bug_id=%s&is_new_user=%s';
use constant RESULT_URL_FAILURE => 'http://input.mozilla.org/bug/thanks/?error=%s';

1;
