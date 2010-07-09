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
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developer are Copyright (C) 2010 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>


# These are constants used by Bugzilla::Test::Search.
# See the comment at the top of that package for a general overview
# of how the search test works, and how the constants are used.
# More detailed information on each constant is available in the comments
# in this file.
package Bugzilla::Test::Search::Constants;
use base qw(Exporter);
use Bugzilla::Constants;

our @EXPORT = qw(
    ATTACHMENT_FIELDS
    COLUMN_TRANSLATION
    COMMENT_FIELDS
    CUSTOM_FIELDS
    FIELD_SIZE
    FIELD_SUBSTR_SIZE
    FLAG_FIELDS
    INJECTION_BROKEN_FIELD
    INJECTION_BROKEN_OPERATOR
    INJECTION_TESTS
    KNOWN_BROKEN
    NUM_BUGS
    NUM_SEARCH_TESTS
    OR_BROKEN
    OR_SKIP
    SKIP_FIELDS
    SUBSTR_SIZE
    TESTS
    TESTS_PER_RUN
    USER_FIELDS
);

# Bug 1 is designed to be found by all the "equals" tests. It has
# multiple values for several fields where other fields only have
# one value.
#
# Bug 2 and 3 have a dependency relationship with Bug 1,
# but show up in "not equals" tests. We do use bug 2 in multiple-value
# tests.
#
# Bug 4 should never show up in any equals test, and has no relationship
# with any other bug. However, it does have all its fields set.
#
# Bug 5 only has values set for mandatory fields, to expose problems
# that happen with "not equals" tests failing to catch bugs that don't
# have a value set at all.
#
# Bug 6 is a clone of Bug 1, but is in a group that the searcher isn't
# in.
use constant NUM_BUGS => 6;

# How many tests there are for each operator/field combination other
# than the "contains" tests.
use constant NUM_SEARCH_TESTS => 3;
# This is how many tests get run for each field/operator.
use constant TESTS_PER_RUN => NUM_SEARCH_TESTS + NUM_BUGS;

# This is how many random characters we generate for most fields' names.
# (Some fields can't be this long, though, so they have custom lengths
# in Bugzilla::Test::Search).
use constant FIELD_SIZE => 30;

# These are the custom fields that are created if the BZ_MODIFY_DATABASE_TESTS
# environment variable is set.
use constant CUSTOM_FIELDS => {
    FIELD_TYPE_FREETEXT,  'cf_freetext',
    FIELD_TYPE_SINGLE_SELECT, 'cf_single_select',
    FIELD_TYPE_MULTI_SELECT, 'cf_multi_select',
    FIELD_TYPE_TEXTAREA, 'cf_textarea',
    FIELD_TYPE_DATETIME, 'cf_datetime',
    FIELD_TYPE_BUG_ID, 'cf_bugid',
};

# This translates fielddefs names into Search column names.
use constant COLUMN_TRANSLATION => {
    creation_ts => 'opendate',
    delta_ts    => 'changeddate',
    work_time => 'actual_time',
};

# Make comment field names to their Bugzilla::Comment accessor.
use constant COMMENT_FIELDS => {
    longdesc  => 'body',
    work_time => 'work_time',
    commenter => 'author',
    'longdescs.isprivate' => 'is_private',
};

# Same as above, for Bugzilla::Attachment.
use constant ATTACHMENT_FIELDS => {
    mimetype => 'contenttype',
    submitter => 'attacher',
    thedata   => 'data',
};

# Same, for Bugzilla::Flag.
use constant FLAG_FIELDS => {
    'flagtypes.name' => 'name',
    'setters.login_name' => 'setter',
    'requestees.login_name' => 'requestee',
};

# These are fields that we don't test. Test::More will mark these
# "TODO & SKIP", and not run tests for them at all.
#
# attachments.isurl can't easily be supported by us, but it's basically
# identical to isprivate and isobsolete for searching, so that's not a big
# loss.
#
# We don't support days_elapsed or owner_idle_time yet.
use constant SKIP_FIELDS => qw(
    attachments.isurl
    owner_idle_time
    days_elapsed
);

# During OR tests, we skip these fields. They basically just don't work
# right in OR tests, and it's too much work to document the exact tests
# that they cause to fail.
use constant OR_SKIP => qw(
    percentage_complete
    flagtypes.name
);

# All the fields that represent users.
use constant USER_FIELDS => qw(
    assigned_to
    reporter
    qa_contact
    commenter
    attachments.submitter
    setters.login_name
    requestees.login_name cc
);

# For the "substr"-type searches, how short of a substring should
# we use?
use constant SUBSTR_SIZE => 20;
# However, for some fields, we use a different size.
use constant FIELD_SUBSTR_SIZE => {
    alias => 12,
    bug_file_loc => 30,
    # Just the month and day.
    deadline => -5,
    creation_ts => -8,
    delta_ts => -8,
    work_time => 3,
    remaining_time => 3,
    see_also => 30,
    target_milestone => 12,
};

################
# Known Broken #
################

# See the KNOWN_BROKEN constant for a general description of these
# "_BROKEN" constants.

# Certain fields fail all the "negative" search tests:
#
# Blocked and Dependson "notequals" only finds bugs that have
# values for the field, but where the dependency list doesn't contain
# the bug you listed. It doesn't find bugs that fully lack values for
# the fields, as it should.
#
# cc "not" matches if any CC'ed user matches, and it fails to match
# if there are no CCs on the bug.
#
# bug_group notequals doesn't find bugs that fully lack groups,
# and matches if there is one group that isn't equal.
#
# bug_file_loc can be NULL, so it gets missed by the normal
# notequals search.
#
# longdescs "notequals" matches if *any* of the values
# are not equal to the string provided.
#
# attachments.* notequals doesn't find bugs that lack attachments.
#
# deadline notequals does not find bugs that lack deadlines
#
# setters notequal doesn't find bugs that fully lack flags.
# (maybe this is OK?)
#
# requestees.login_name doesn't find bugs that fully lack requestees.
use constant NEGATIVE_BROKEN => (
    'attachments.isobsolete'  => { contains => [5] },
    'attachments.ispatch'     => { contains => [5] },
    'attachments.isprivate'   => { contains => [5] },
    'attach_data.thedata'     => { contains => [5] },
    'attachments.description' => { contains => [5] },
    'attachments.filename'    => { contains => [5] },
    'attachments.mimetype'    => { contains => [5] },
    'attachments.submitter'   => { contains => [5] },
    blocked      => { contains => [3,4,5] },
    bug_file_loc => { contains => [5] },
    bug_group    => { contains => [1,5] },
    cc           => { contains => [1,5] },
    deadline     => { contains => [5] },
    dependson    => { contains => [2,4,5] },
    longdesc     => { contains => [1] },
    'longdescs.isprivate'   => { contains => [1] },
    'requestees.login_name' => { contains => [3,4,5] },
    'setters.login_name'    => { contains => [5] },
    work_time               => { contains => [1] },
    # Custom fields are busted because they can be NULL.
    FIELD_TYPE_FREETEXT, { contains => [5] },
    FIELD_TYPE_BUG_ID,   { contains => [5] },
    FIELD_TYPE_DATETIME, { contains => [5] },
    FIELD_TYPE_TEXTAREA, { contains => [5] },
);

# Shared between greaterthan and greaterthaneq.
#
# As with other fields, longdescs greaterthan matches if any comment
# matches (which might be OK).
#
# Same for keywords, bug_group, and cc. Logically, all of these might
# be OK, but it makes the operation not the logical reverse of
# lessthaneq. What we're really saying here by marking these broken
# is that there ought to be some way of searching "all ccs" vs "any cc"
# (and same for the other fields).
use constant GREATERTHAN_BROKEN => (
    bug_group => { contains => [1] },
    cc        => { contains => [1] },
    keywords  => { contains => [1] },
    longdesc  => { contains => [1] },
    FIELD_TYPE_MULTI_SELECT, { contains => [1] },
);

# allwords and allwordssubstr have these broken tests in common.
#
# allwordssubstr work_time only matches against a single comment,
# instead of matching against all comments on a bug. Same is true
# for the other longdesc fields, cc, keywords, and bug_group.
use constant ALLWORDS_BROKEN => (
    bug_group => { contains => [1] },
    cc        => { contains => [1] },
    keywords  => { contains => [1] },
    longdesc  => { contains => [1] },
    work_time => { contains => [1] },
);

# nowords and nowordssubstr have these broken tests in common.
#
# flagtypes.name doesn't match bugs without flags.
# cc, longdescs.isprivate, and bug_group actually work properly in
# terms of excluding bug 1 (since we exclude all values in the search,
# on our test), but still fail at including bug 5.
# The longdesc* and work_time fields, coincidentally, work completely
# correctly, possibly because there's only one comment on bug 5.
use constant NOWORDS_BROKEN => (
    NEGATIVE_BROKEN,
    'flagtypes.name' => { contains => [5] },
    bug_group        => { contains => [5] },
    cc               => { contains => [5] },
    longdesc         => {},
    work_time        => {},
    'longdescs.isprivate' => {},
);

# Fields that don't generally work at all with changed* searches, but
# probably should.
use constant CHANGED_BROKEN => (
    classification => { contains => [1] },
    commenter => { contains => [1] },
    percentage_complete     => { contains => [1] },
    'requestees.login_name' => { contains => [1] },
    'setters.login_name'    => { contains => [1] },
    delta_ts                => { contains => [1] },
);

# These are additional broken tests that changedfrom and changedto
# have in common.
use constant CHANGED_VALUE_BROKEN => (
    bug_group        => { contains => [1] },
    cc               => { contains => [1] },
    estimated_time   => { contains => [1] },
    'flagtypes.name' => { contains => [1] },
    keywords  => { contains => [1] },
    work_time => { contains => [1] },
    FIELD_TYPE_MULTI_SELECT, { contains => [1] },
);


# Any test listed in KNOWN_BROKEN gets marked TODO by Test::More
# (using some complex code in Bugzilla::Test::Seach::FieldTest).
# This means that if you run the test under "prove -v", these tests will
# still show up as "not ok", but the test suite results won't show them
# as a failure.
#
# This constant contains operators as keys, which point to hashes. The hashes
# have field names as keys. Each field name points to a hash describing
# how that field/operator combination is broken. The "contains"
# array specifies that that particular "contains" test is expected
# to fail. If "search" is set to 1, then we expect the creation of the
# Bugzilla::Search object to fail.
#
# To allow handling custom fields, you can also use the field type as a key
# instead of the field name. Specifying explicit field names always overrides
# specifying a field type.
#
# Sometimes the operators have multiple tests, and one of them works
# while the other fails. In this case, we have a special override for
# "operator-value", which uniquely identifies tests.
use constant KNOWN_BROKEN => {
    notequals    => { NEGATIVE_BROKEN },
    notsubstring => { NEGATIVE_BROKEN },
    notregexp    => { NEGATIVE_BROKEN },

    # percentage_complete doesn't match bugs with 0 hours worked or remaining.
    #
    # longdescs.isprivate matches if any comment matches, instead of if all
    # comments match. Same for longdescs and work_time. (Commenter is probably
    # also broken in this way, but all our comments come from the same user.) 
    # Also, the attachments ones don't find bugs that have no attachments 
    # at all (which might be OK?).
    lessthan   => {
        'longdescs.isprivate'   => { contains => [1] },
        work_time => { contains => [1,2,3,4] },
    },
    # The lessthaneq tests are broken for the same reasons, but they work
    # slightly differently so they have a different set of broken tests.
    lessthaneq => {
        'longdescs.isprivate' => { contains => [1] },
        work_time => { contains => [2,3,4] },
    },

    greaterthan => { GREATERTHAN_BROKEN },

    # percentage_complete is broken -- it won't match equal values.
    greaterthaneq => {
        GREATERTHAN_BROKEN,
        percentage_complete => { contains => [2] },
    },

    # percentage_complete doesn't do a numeric comparison, so
    # it doesn't find decimal values.
    anyexact => {
        percentage_complete => { contains => [2] },
    },
    # bug_group anywordssubstr returns all our bugs. Not sure why.
    anywordssubstr => {
        percentage_complete => { contains => [2] },
        bug_group => { contains => [3,4,5] },
    },

    'allwordssubstr-<1>' => { ALLWORDS_BROKEN },
    # flagtypes.name does not work here, probably because they all try to
    # match against a single flag.
    # Same for attach_data.thedata.
    'allwords-<1>' => {
        ALLWORDS_BROKEN,
        'attach_data.thedata' => { contains => [1] },
        'flagtypes.name' => { contains => [1] },
    },

    nowordssubstr => { NOWORDS_BROKEN },
    # attach_data.thedata doesn't match properly with any of the plain
    # "words" searches. Also, bug 5 doesn't match because it lacks
    # attachments.
    nowords => {
        NOWORDS_BROKEN,
        'attach_data.thedata' => { contains => [1,5] },
    },

    # anywords searches don't work on decimal values.
    # bug_group anywords returns all bugs.
    # attach_data doesn't work (perhaps because it's the entire
    # data, or some problem with the regex?).
    anywords => {
        'attach_data.thedata' => { contains => [1] },
        bug_group => { contains => [2,3,4,5] },
        work_time => { contains => [1] },
    },
    'anywords-<1> <2>' => {
        bug_group => { contains => [3,4,5] },
        percentage_complete => { contains => [2] },
        'attach_data.thedata' => { contains => [1,2] },
        work_time => { contains => [1,2] },
    },

    # setters.login_name and requestees.login name aren't tracked individually
    # in bugs_activity, so can't be searched using this method.
    #
    # percentage_complete isn't tracked in bugs_activity (and it would be
    # really hard to track). However, it adds a 0=0 term instead of using
    # the changed* charts or simply denying them.
    #
    # delta_ts changedbefore/after should probably search for bugs based
    # on their delta_ts.
    #
    # creation_ts changedbefore/after should search for bug creation dates.
    #
    # The commenter field changedbefore/after should search for comment
    # creation dates.
    #
    # classification isn't being tracked properly in bugs_activity, I think.
    #
    # attach_data.thedata should search when attachments were created and
    # who they were created by.
    'changedbefore' => {
        CHANGED_BROKEN,
        'attach_data.thedata' => { contains => [1] },
        creation_ts => { contains => [1,5] },
        # attachments.* finds values where the date matches exactly.
        'attachments.description' => { contains => [2] },
        'attachments.filename'    => { contains => [2] },
        'attachments.isobsolete'  => { contains => [2] },
        'attachments.ispatch'     => { contains => [2] },
        'attachments.isprivate'   => { contains => [2] },
        'attachments.mimetype'    => { contains => [2] },
    },
    'changedafter' => {
        'attach_data.thedata' => { contains => [2,3,4] },
        classification => { contains => [2,3,4] },
        commenter   => { contains => [2,3,4] },
        creation_ts => { contains => [2,3,4] },
        delta_ts    => { contains => [2,3,4] },
        percentage_complete => { contains => [2,3,4] },
        'requestees.login_name' => { contains => [2,3,4] },
        'setters.login_name'    => { contains => [2,3,4] },
    },
    changedfrom => {
        CHANGED_BROKEN,
        CHANGED_VALUE_BROKEN,
        # All fields should have a way to search for "changing
        # from a blank value" probably.
        blocked   => { contains => [3,4,5] },
        dependson => { contains => [2,4,5] },
        FIELD_TYPE_BUG_ID, { contains => [5] },
    },
    # changeto doesn't find work_time changes (probably due to decimal/string
    # stuff). Same for remaining_time and estimated_time.
    #
    # multi-valued fields are stored as comma-separated strings, so you
    # can't do changedfrom/to on them.
    #
    # Perhaps commenter can either tell you who the last commenter was,
    # or if somebody commented at a given time (combined with other
    # charts).
    #
    # longdesc changedto/from doesn't do anything; maybe it should.
    # Same for attach_data.thedata.
    changedto => {
        CHANGED_BROKEN,
        CHANGED_VALUE_BROKEN,
        'attach_data.thedata' => { contains => [1] },
        longdesc         => { contains => [1] },
        remaining_time   => { contains => [1] },
    },
    changedby => {
        CHANGED_BROKEN,
        # This should probably search the attacher or anybody who changed
        # anything about an attachment at all.
        'attach_data.thedata' => { contains => [1] },
        # This should probably search the reporter.
        creation_ts => { contains => [1] },
    },
};

#############
# Overrides #
#############

# These overrides are used in the TESTS constant, below.

# Regex tests need unique test values for certain fields.
use constant REGEX_OVERRIDE => {
    'attachments.mimetype'  => { value => '^text/x-1-' },
    bug_file_loc => { value => '^http://1-' },
    see_also  => { value => '^http://1-' },
    blocked   => { value => '^<1>$' },
    dependson => { value => '^<1>$' },
    bug_id    => { value => '^<1>$' },
    'attachments.isobsolete' => { value => '^1'},
    'attachments.ispatch'    => { value => '^1'},
    'attachments.isprivate'  => { value => '^1' },
    cclist_accessible        => { value => '^1' },
    reporter_accessible      => { value => '^1' },
    everconfirmed            => { value => '^1' },
    'longdescs.isprivate'    => { value => '^1' },
    creation_ts => { value => '^2037-01-01' },
    delta_ts    => { value => '^2037-01-01' },
    deadline    => { value => '^2037-02-01' },
    estimated_time => { value => '^1.0' },
    remaining_time => { value => '^9.0' },
    work_time      => { value => '^1.0' },
    longdesc       => { value => '^1-' },
    percentage_complete => { value => '^10.0' },
    FIELD_TYPE_BUG_ID, { value => '^<1>$' },
    FIELD_TYPE_DATETIME, { value => '^2037-03-01' }
};

# Common overrides between lessthan and lessthaneq.
use constant LESSTHAN_OVERRIDE => (
    alias             => { contains => [1,5] },
    estimated_time    => { contains => [1,5] },
    qa_contact        => { contains => [1,5] },
    resolution        => { contains => [1,5] },
    status_whiteboard => { contains => [1,5] },
);

# The mandatorily-set fields have values higher than <1>,
# so bug 5 shows up.
use constant GREATERTHAN_OVERRIDE => (
    classification => { contains => [2,3,4,5] },
    assigned_to  => { contains => [2,3,4,5] },
    bug_id       => { contains => [2,3,4,5] },
    bug_severity => { contains => [2,3,4,5] },
    bug_status   => { contains => [2,3,4,5] },
    component    => { contains => [2,3,4,5] },
    commenter    => { contains => [2,3,4,5] },
    op_sys       => { contains => [2,3,4,5] },
    priority     => { contains => [2,3,4,5] },
    product      => { contains => [2,3,4,5] },
    reporter     => { contains => [2,3,4,5] },
    rep_platform => { contains => [2,3,4,5] },
    short_desc   => { contains => [2,3,4,5] },
    version      => { contains => [2,3,4,5] },
    target_milestone => { contains => [2,3,4,5] },
    # Bug 2 is the only bug besides 1 that has a Requestee set.
    'requestees.login_name'  => { contains => [2] },
    FIELD_TYPE_SINGLE_SELECT, { contains => [2,3,4,5] },
    # Override SINGLE_SELECT for resolution.
    resolution => { contains => [2,3,4] },
);

# For all positive multi-value types.
use constant MULTI_BOOLEAN_OVERRIDE => (
    'attachments.ispatch'    => { value => '1,1', contains => [1] },
    'attachments.isobsolete' => { value => '1,1', contains => [1] },
    'attachments.isprivate'  => { value => '1,1', contains => [1] },
    cclist_accessible        => { value => '1,1', contains => [1] },
    reporter_accessible      => { value => '1,1', contains => [1] },
    'longdescs.isprivate'    => { value => '1,1', contains => [1] },
    everconfirmed            => { value => '1,1', contains => [1] },
);

# Same as above, for negative multi-value types.
use constant NEGATIVE_MULTI_BOOLEAN_OVERRIDE => (
    'attachments.ispatch'    => { value => '1,1', contains => [2,3,4,5] },
    'attachments.isobsolete' => { value => '1,1', contains => [2,3,4,5] },
    'attachments.isprivate'  => { value => '1,1', contains => [2,3,4,5] },
    cclist_accessible        => { value => '1,1', contains => [2,3,4,5] },
    reporter_accessible      => { value => '1,1', contains => [2,3,4,5] },
    'longdescs.isprivate'    => { value => '1,1', contains => [2,3,4,5] },
    everconfirmed            => { value => '1,1', contains => [2,3,4,5] },
);

# For anyexact and anywordssubstr
use constant ANY_OVERRIDE => (
    'work_time' => { value => '1.0,2.0' },
    dependson => { value => '<1>,<3>', contains => [1,3] },
    MULTI_BOOLEAN_OVERRIDE,
);

# For all the changed* searches. The ones that have empty contains
# are fields that never change in value, or will never be rationally
# tracked in bugs_activity.
use constant CHANGED_OVERRIDE => (
    'attachments.submitter' => { contains => [] },
    bug_id    => { contains => [] },
    reporter  => { contains => [] },
);

#########
# Tests #
#########

# The basic format of this is a hashref, where the keys are operators,
# and each operator has an arrayref of tests that it runs. The tests
# are hashrefs, with the following possible keys:
#
# contains: This is a list of bug numbers that the search is expected
#           to contain. (This is bug numbers, like 1,2,3, not the bug
#           ids. For a description of each bug number, see NUM_BUGS.)
#           Any bug not listed in "contains" must *not* show up in the
#           search result.
# value: The value that you're searching for. There are certain special
#        codes that will be replaced with bug values when the tests are
#        run. In these examples below, "#" indicates a bug number:
#
#        <#> - The field value for this bug.
#
#              For any operator that has the string "word" in it, this is
#              *all* the values for the current field from the numbered bug,
#              joined by a space.
#
#              If the operator has the string "substr" in it, then we
#              take a substring of the value (for single-value searches)
#              or we take a substring of each value and join them (for
#              multi-value "word" searches). The length of the substring
#              is determined by the SUBSTR_SIZE constants above.)
#
#              For other operators, this just becomes the first value from
#              the field for the numbered bug.
#
#              So, if we were running the "equals" test and checking the
#              cc field, <1> would become the login name of the first cc on
#              Bug 1. If we did an "anywords" search test, it would become
#              a space-separated string of the login names of all the ccs
#              on Bug 1. If we did an "anywordssubstr" search test, it would
#              become a space-separated string of the first few characters
#              of each CC's login name on Bug 1.
#              
#        <#-id> - The bug id of the numbered bug.
#        <#-reporter> - The login name of the numbered bug's reporter.
#        <#-delta> - The delta_ts of the numbered bug.
#
# escape: If true, we will call quotemeta() on the value immediately
#         before passing it to Search.pm.
#
# transform: A function to call on any field value before inserting
#            it for a <#> replacement. The transformation function
#            gets all of the bug's values for the field as its arguments.
# if_equal: This allows you to override "contains" for the case where
#           the transformed value (from calling the "transform" function)
#           is equal to the original value.
#
# override: This allows you to override "contains" and "values" for
#           certain fields.
use constant TESTS => {
    equals => [
        { contains => [1], value => '<1>' },
    ],
    notequals => [
        { contains => [2,3,4,5], value => '<1>' },
    ],
    substring => [
        { contains => [1], value => '<1>' },
    ],
    casesubstring => [
        { contains => [1], value => '<1>' },
        { contains => [], value => '<1>', transform => sub { lc($_[0]) },
          extra_name => 'lc', if_equal => { contains => [1] } },
    ],
    notsubstring => [
        { contains => [2,3,4,5], value => '<1>' },
    ],
    regexp => [
        { contains => [1], value => '<1>', escape => 1 },
        { contains => [1], value => '^1-', override => REGEX_OVERRIDE },
    ],
    notregexp => [
        { contains => [2,3,4,5], value => '<1>', escape => 1 },
        { contains => [2,3,4,5], value => '^1-', override => REGEX_OVERRIDE },
    ],
    lessthan => [
        { contains => [1], value => 2, 
          override => {
              # A lot of these contain bug 5 because an empty value is validly
              # less than the specified value.
              bug_file_loc => { value => 'http://2-' },
              see_also     => { value => 'http://2-' },
              'attachments.mimetype' => { value => 'text/x-2-' },
              blocked   => { value => '<4-id>', contains => [1,2] },
              dependson => { value => '<3-id>', contains => [1,3] },
              bug_id    => { value => '<2-id>' },
              'attachments.isprivate'  => { value => 1, contains => [2,3,4] },
              'attachments.isobsolete' => { value => 1, contains => [2,3,4] },
              'attachments.ispatch'    => { value => 1, contains => [2,3,4] },
              cclist_accessible        => { value => 1, contains => [2,3,4,5] },
              reporter_accessible      => { value => 1, contains => [2,3,4,5] },
              'longdescs.isprivate'    => { value => 1, contains => [2,3,4,5] },
              everconfirmed            => { value => 1, contains => [2,3,4,5] },
              creation_ts => { value => '2037-01-02', contains => [1,5] },
              delta_ts    => { value => '2037-01-02', contains => [1,5] },
              deadline    => { value => '2037-02-02' },
              remaining_time => { value => 10, contains => [1,5] },
              percentage_complete => { value => 11, contains => [1,5] },
              longdesc => { value => '2-', contains => [1,5] },
              work_time => { value => 1, contains => [5] },
              FIELD_TYPE_BUG_ID, { value => '<2>' },
              FIELD_TYPE_DATETIME, { value => '2037-03-02' },
              LESSTHAN_OVERRIDE,
          }
        },
    ],
    lessthaneq => [
        { contains => [1], value => '<1>',
          override => {
              'attachments.isobsolete' => { value => 0, contains => [2,3,4] },
              'attachments.ispatch'    => { value => 0, contains => [2,3,4] },
              'attachments.isprivate'  => { value => 0, contains => [2,3,4] },
              cclist_accessible        => { value => 0, contains => [2,3,4,5] },
              reporter_accessible      => { value => 0, contains => [2,3,4,5] },
              'longdescs.isprivate'    => { value => 0, contains => [2,3,4,5] },
              everconfirmed            => { value => 0, contains => [2,3,4,5] },
              blocked   => { contains => [1,2] },
              dependson => { contains => [1,3] },
              creation_ts    => { contains => [1,5] },
              delta_ts       => { contains => [1,5] },
              remaining_time => { contains => [1,5] },
              longdesc       => { contains => [1,5] },
              percentage_complete => { contains => [1,5] },
              work_time => { value => 1, contains => [1,5] },
              LESSTHAN_OVERRIDE,
          },
        },
    ],
    greaterthan => [
        { contains => [2,3,4], value => '<1>',
          override => {
              dependson => { contains => [3] },
              blocked   => { contains => [2] },
              'attachments.ispatch'    => { value => 0, contains => [1] },
              'attachments.isobsolete' => { value => 0, contains => [1] },
              'attachments.isprivate'  => { value => 0, contains => [1] },
              cclist_accessible        => { value => 0, contains => [1] },
              reporter_accessible      => { value => 0, contains => [1] },
              'longdescs.isprivate'    => { value => 0, contains => [1] },
              everconfirmed            => { value => 0, contains => [1] },
              'flagtypes.name'         => { value => 2, contains => [2,3,4] },
              GREATERTHAN_OVERRIDE,
          },
        },
    ],
    greaterthaneq => [
        { contains => [2,3,4], value => '<2>',
          override => {
              'attachments.ispatch'    => { value => 1, contains => [1] },
              'attachments.isobsolete' => { value => 1, contains => [1] },
              'attachments.isprivate'  => { value => 1, contains => [1] },
              cclist_accessible        => { value => 1, contains => [1] },
              reporter_accessible      => { value => 1, contains => [1] },
              'longdescs.isprivate'    => { value => 1, contains => [1] },
              everconfirmed            => { value => 1, contains => [1] },
              dependson => { value => '<3>', contains => [1,3] },
              blocked   => { contains => [1,2] },
              GREATERTHAN_OVERRIDE,
          }
        },
    ],
    matches => [
        { contains => [1], value => '<1>' },
    ],
    notmatches => [
        { contains => [2,3,4,5], value => '<1>' },
    ],
    anyexact => [
        { contains => [1,2], value => '<1>, <2>', 
          override => { ANY_OVERRIDE } },
    ],
    anywordssubstr => [
        { contains => [1,2], value => '<1> <2>', 
          override => { ANY_OVERRIDE } },
    ],
    allwordssubstr => [
        { contains => [1], value => '<1>',
          override => { MULTI_BOOLEAN_OVERRIDE } },
        { contains => [], value => '<1>,<2>',
          override => {
              dependson => { value => '<1-id> <3-id>', contains => [] },
          }
        },
    ],
    nowordssubstr => [
        { contains => [2,3,4,5], value => '<1>',
          override => {
              # longdescs.isprivate translates to "1 0", so no bugs should
              # show up.
              'longdescs.isprivate' => { contains => [] },
              # 1.0 0.0 exludes bug 5.
              # XXX However, it also shouldn't match 2, 3, or 4, because
              # they contain at least one comment with 0.0 work_time.
              work_time => { contains => [2,3,4] },
          }
        },
    ],
    anywords => [
        { contains => [1], value => '<1>',
          override => {
              MULTI_BOOLEAN_OVERRIDE,
              work_time => { value => '1.0', contains => [1] },
          }
        },
        { contains => [1,2], value => '<1> <2>',
          override => {
              MULTI_BOOLEAN_OVERRIDE,
              dependson => { value => '<1> <3>', contains => [1,3] },
              work_time => { value => '1.0 2.0' },
          },
        },
    ],
    allwords => [
        { contains => [1], value => '<1>',
          override => { MULTI_BOOLEAN_OVERRIDE } },
        { contains => [], value => '<1> <2>',
          override => {
            dependson => { contains => [], value => '<2-id> <3-id>' }
          }
        },
    ],
    nowords => [
        { contains => [2,3,4,5], value => '<1>',
          override => {
              # longdescs.isprivate translates to "1 0", so no bugs should
              # show up.
              'longdescs.isprivate' => { contains => [] },
              # 1.0 0.0 exludes bug 5.
              # XXX However, it also shouldn't match 2, 3, or 4, because
              # they contain at least one comment with 0.0 work_time.
              work_time => { contains => [2,3,4] },
          }
        },
    ],

    changedbefore => [
        { contains => [1], value => '<2-delta>',
          override => {
              CHANGED_OVERRIDE,
              creation_ts => { contains => [1,5] },
              blocked   => { contains => [1,2] },
              dependson => { contains => [1,3] },
              longdesc => { contains => [1,2,5] },
          }
        },
    ],
    changedafter => [
        { contains => [2,3,4], value => '<1-delta>',
          override => { 
              CHANGED_OVERRIDE,
              creation_ts => { contains => [2,3,4] },
              # We only change this for one bug, and it doesn't match.
              'longdescs.isprivate' => { contains => [] },
              # Same for everconfirmed.
              'everconfirmed' => { contains => [] },
              # For blocked and dependson, they have the delta_ts of bug1
              # in the bugs_activity table, so they won't ever match.
              blocked   => { contains => [] },
              dependson => { contains => [] },
          }
        },
    ],
    changedfrom => [
        { contains => [1], value => '<1>',
          override => {
              CHANGED_OVERRIDE,
              # The test never changes an already-set dependency field, but
              # we *can* attempt to test searching against an empty value,
              # which should get us some bugs.
              blocked   => { value => '', contains => [1,2] },
              dependson => { value => '', contains => [1,3] },
              FIELD_TYPE_BUG_ID, { value => '', contains => [1,2,3,4] },
              # longdesc changedfrom doesn't make any sense.
              longdesc => { contains => [] },
              # Nor does creation_ts changedfrom.
              creation_ts => { contains => [] },
              'attach_data.thedata' => { contains => [] },
              bug_id => { value => '<1-id>', contains => [] },
          },
        },
    ],
    changedto => [
        { contains => [1], value => '<1>',
          override => {
              CHANGED_OVERRIDE,
              # I can't imagine any use for creation_ts changedto.
              creation_ts => { contains => [] },
          }
        },
    ],
    changedby => [
        { contains => [1], value => '<1-reporter>',
          override => {
              CHANGED_OVERRIDE,
              blocked   => { contains => [1,2] },
              dependson => { contains => [1,3] },
          },
        },
    ],
};

# Fields that do not behave as we expect, for InjectionTest.
# search => 1 means the Bugzilla::Search creation fails.
# sql_error is a regex that specifies a SQL error that's OK for us to throw.
# operator_ok overrides the "brokenness" of certain operators, so that they
# are always OK for that field/operator combination.
use constant INJECTION_BROKEN_FIELD => {
    # Pg can't run injection tests against integer or date fields. See bug 577557.
    'attachments.isobsolete' => { db_skip => ['Pg'] },
    'attachments.ispatch'    => { db_skip => ['Pg'] },
    'attachments.isprivate'  => { db_skip => ['Pg'] },
    'attachments.isurl'      => { db_skip => ['Pg'] },
    blocked                  => { db_skip => ['Pg'] },
    bug_id                   => { db_skip => ['Pg'] },
    cclist_accessible        => { db_skip => ['Pg'] },
    creation_ts              => { db_skip => ['Pg'] },
    days_elapsed             => { db_skip => ['Pg'] },
    dependson                => { db_skip => ['Pg'] },
    deadline                 => { db_skip => ['Pg'] },
    delta_ts                 => { db_skip => ['Pg'] },
    estimated_time           => { db_skip => ['Pg'] },
    everconfirmed            => { db_skip => ['Pg'] },
    'longdescs.isprivate'    => { db_skip => ['Pg'] },
    percentage_complete      => { db_skip => ['Pg'] },
    remaining_time           => { db_skip => ['Pg'] },
    reporter_accessible      => { db_skip => ['Pg'] },
    work_time                => { db_skip => ['Pg'] },
    FIELD_TYPE_BUG_ID,          { db_skip => ['Pg'] },
    FIELD_TYPE_DATETIME,        { db_skip => ['Pg'] },
    owner_idle_time => { search => 1 },
    keywords => {
        search => 1,
        operator_ok => [qw(allwordssubstr anywordssubstr casesubstring
                           changedfrom changedto greaterthan greaterthaneq
                           lessthan lessthaneq notregexp notsubstring
                           nowordssubstr regexp substring anywords
                           notequals nowords)]
    },
};

# Operators that do not behave as we expect, for InjectionTest.
# search => 1 means the Bugzilla::Search creation fails, but
# field_ok contains fields that it does actually succeed for.
use constant INJECTION_BROKEN_OPERATOR => {
    changedafter  => { search => 1 },
    changedbefore => { search => 1 },
    changedby     => { search => 1 },
};

# Tests run by Bugzilla::Test::Search::InjectionTest.
# We have to make sure the values are all one word or they'll be split
# up by the multi-word tests.
use constant INJECTION_TESTS => (
    { value => ';SEMICOLON_TEST' },
    { value => '--COMMENT_TEST'  },
    { value => "'QUOTE_TEST" },
    { value => "';QUOTE_SEMICOLON_TEST" },
    { value => '/*STAR_COMMENT_TEST' }
);

# This overrides KNOWN_BROKEN for OR configurations.
# It indicates that these combinations are broken in some way that they
# aren't broken when alone, because they don't return what they logically
# should when put into an OR.
use constant OR_BROKEN => {
    # Multi-value fields search on individual values, so "equals" OR "notequals"
    # returns nothing, when it should instead logically return everything.
    'blocked-equals' => {
        'blocked-notequals' => { contains => [1,2,3,4,5] },
    },
    'dependson-equals' => {
        'dependson-notequals' => { contains => [1,2,3,4,5] },
    },
    'bug_group-equals' => {
        'bug_group-notequals' => { contains => [1,2,3,4,5] },
    },
    'cc-equals' => {
        'cc-notequals' => { contains => [1,2,3,4,5] },
    },
    'commenter-equals' => {
        'commenter-notequals' => { contains => [1,2,3,4,5] },
        'longdesc-notequals'  => { contains => [2,3,4,5] },
        'longdescs.isprivate-notequals' => { contains => [2,3,4,5] },
        'work_time-notequals' => { contains => [2,3,4,5] },
    },
    'commenter-notequals' => {
        'commenter-equals' => { contains => [1,2,3,4,5] },
        'longdesc-equals'  => { contains => [1] },
        'longdescs.isprivate-equals' => { contains => [1] },
        'work_time-equals' => { contains => [1] },
    },
};

1;
