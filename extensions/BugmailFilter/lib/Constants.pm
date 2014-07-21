# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugmailFilter::Constants;
use strict;

use base qw(Exporter);

our @EXPORT = qw(
    FAKE_FIELD_NAMES
    IGNORE_FIELDS
    FIELD_DESCRIPTION_OVERRIDE
    FILTER_RELATIONSHIPS
);

use Bugzilla::Constants;

# these are field names which are inserted into X-Bugzilla-Changed-Field-Names
# header but are not real fields

use constant FAKE_FIELD_NAMES => [
    {
        name        => 'comment.created',
        description => 'Comment created',
    },
    {
        name        => 'attachment.created',
        description => 'Attachment created',
    },
];

# these fields don't make any sense to filter on

use constant IGNORE_FIELDS => qw(
    attach_data.thedata
    attachments.submitter
    cf_last_resolved
    commenter
    comment_tag
    creation_ts
    days_elapsed
    delta_ts
    everconfirmed
    last_visit_ts
    longdesc
    longdescs.count
    owner_idle_time
    reporter
    reporter_accessible
    setters.login_name
    tag
    votes
);

# override the description of some fields

use constant FIELD_DESCRIPTION_OVERRIDE => {
    bug_id => 'Bug Created',
};

# relationship / int mappings
# _should_drop() also needs updating when this const is changed

use constant FILTER_RELATIONSHIPS => [
    {
        name    => 'Assignee',
        value   => 1,
    },
    {
        name    => 'Not Assignee',
        value   => 2,
    },
    {
        name    => 'Reporter',
        value   => 3,
    },
    {
        name    => 'Not Reporter',
        value   => 4,
    },
    {
        name    => 'QA Contact',
        value   => 5,
    },
    {
        name    => 'Not QA Contact',
        value   => 6,
    },
    {
        name    => "CC'ed",
        value   => 7,
    },
    {
        name    => "Not CC'ed",
        value   => 8,
    },
    {
        name    => 'Watching',
        value   => 9,
    },
    {
        name    => 'Not Watching',
        value   => 10,
    },
    {
        name    => 'Mentoring',
        value   => 11,
    },
    {
        name    => 'Not Mentoring',
        value   => 12,
    },
];

1;
