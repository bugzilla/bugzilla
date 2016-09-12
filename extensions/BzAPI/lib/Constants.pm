# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BzAPI::Constants;

use strict;

use base qw(Exporter);
our @EXPORT = qw(
    USER_FIELDS
    BUG_FIELD_MAP
    BOOLEAN_TYPE_MAP
    ATTACHMENT_FIELD_MAP
    DEFAULT_BUG_FIELDS
    DEFAULT_ATTACHMENT_FIELDS

    BZAPI_DOC
);

# These are fields that are normally exported as a single value such
# as the user's email. BzAPI needs to convert them to user objects
# where possible.
use constant USER_FIELDS => (qw(
    assigned_to
    cc
    creator
    qa_contact
    reporter
));

# Convert old field names from old to new
use constant BUG_FIELD_MAP => {
    'opendate'            => 'creation_time', # query
    'creation_ts'         => 'creation_time',
    'changeddate'         => 'last_change_time', # query
    'delta_ts'            => 'last_change_time',
    'bug_id'              => 'id',
    'rep_platform'        => 'platform',
    'bug_severity'        => 'severity',
    'bug_status'          => 'status',
    'short_desc'          => 'summary',
    'bug_file_loc'        => 'url',
    'status_whiteboard'   => 'whiteboard',
    'reporter'            => 'creator',
    'reporter_realname'   => 'creator_realname',
    'cclist_accessible'   => 'is_cc_accessible',
    'reporter_accessible' => 'is_creator_accessible',
    'everconfirmed'       => 'is_confirmed',
    'dependson'           => 'depends_on',
    'blocked'             => 'blocks',
    'attachment'          => 'attachments',
    'flag'                => 'flags',
    'flagtypes.name'      => 'flag',
    'bug_group'           => 'group',
    'group'               => 'groups',
    'longdesc'            => 'comment',
    'bug_file_loc_type'   => 'url_type',
    'bugidtype'           => 'id_mode',
    'longdesc_type'       => 'comment_type',
    'short_desc_type'     => 'summary_type',
    'status_whiteboard_type' => 'whiteboard_type',
    'emailassigned_to1'   => 'email1_assigned_to',
    'emailassigned_to2'   => 'email2_assigned_to',
    'emailcc1'            => 'email1_cc',
    'emailcc2'            => 'email2_cc',
    'emailqa_contact1'    => 'email1_qa_contact',
    'emailqa_contact2'    => 'email2_qa_contact',
    'emailreporter1'      => 'email1_creator',
    'emailreporter2'      => 'email2_creator',
    'emaillongdesc1'      => 'email1_comment_creator',
    'emaillongdesc2'      => 'email2_comment_creator',
    'emailtype1'          => 'email1_type',
    'emailtype2'          => 'email2_type',
    'chfieldfrom'         => 'changed_after',
    'chfieldto'           => 'changed_before',
    'chfield'             => 'changed_field',
    'chfieldvalue'        => 'changed_field_to',
    'deadlinefrom'        => 'deadline_after',
    'deadlineto'          => 'deadline_before',
    'attach_data.thedata' => 'attachment.data',
    'longdescs.isprivate' => 'comment.is_private',
    'commenter'           => 'comment.creator',
    'requestees.login_name' => 'flag.requestee',
    'setters.login_name'  => 'flag.setter',
    'days_elapsed'        => 'idle',
    'owner_idle_time'     => 'assignee_idle',
    'dup_id'              => 'dupe_of',
    'isopened'            => 'is_open',
    'flag_type'           => 'flag_types',
    'attachments.submitter'   => 'attachment.attacher',
    'attachments.filename'    => 'attachment.file_name',
    'attachments.description' => 'attachment.description',
    'attachments.delta_ts'    => 'attachment.last_change_time',
    'attachments.isobsolete'  => 'attachment.is_obsolete',
    'attachments.ispatch'     => 'attachment.is_patch',
    'attachments.isprivate'   => 'attachment.is_private',
    'attachments.mimetype'    => 'attachment.content_type',
    'attachments.date'        => 'attachment.creation_time',
    'attachments.attachid'    => 'attachment.id',
    'attachments.flag'        => 'attachment.flags',
    'attachments.token'       => 'attachment.update_token'
};

# Convert from old boolean chart type names to new names
use constant BOOLEAN_TYPE_MAP => {
    'equals'                 => 'equals',
    'not_equals'             => 'notequals',
    'equals_any'             => 'anyexact',
    'contains'               => 'substring',
    'not_contains'           => 'notsubstring',
    'case_contains'          => 'casesubstring',
    'contains_any'           => 'anywordssubstr',
    'not_contains_any'       => 'nowordssubstr',
    'contains_all'           => 'allwordssubstr',
    'contains_any_words'     => 'anywords',
    'not_contains_any_words' => 'nowords',
    'contains_all_words'     => 'allwords',
    'regex'                  => 'regexp',
    'not_regex'              => 'notregexp',
    'less_than'              => 'lessthan',
    'greater_than'           => 'greaterthan',
    'changed_before'         => 'changedbefore',
    'changed_after'          => 'changedafter',
    'changed_from'           => 'changedfrom',
    'changed_to'             => 'changedto',
    'changed_by'             => 'changedby',
    'matches'                => 'matches'
};

# Convert old attachment field names from old to new
use constant ATTACHMENT_FIELD_MAP => {
    'submitter'   => 'attacher',
    'description' => 'description',
    'filename'    => 'file_name',
    'delta_ts'    => 'last_change_time',
    'isobsolete'  => 'is_obsolete',
    'ispatch'     => 'is_patch',
    'isprivate'   => 'is_private',
    'mimetype'    => 'content_type',
    'contenttypeentry' => 'content_type',
    'date'        => 'creation_time',
    'attachid'    => 'id',
    'desc'        => 'description',
    'flag'        => 'flags',
    'type'        => 'content_type',
};

# A base link to the current BzAPI Documentation.
use constant BZAPI_DOC => 'https://wiki.mozilla.org/Bugzilla:BzAPI';

1;
