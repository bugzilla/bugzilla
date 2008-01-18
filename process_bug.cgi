#!/usr/bin/perl -wT
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
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Terry Weissman <terry@mozilla.org>
#                 Dan Mosedale <dmose@mozilla.org>
#                 Dave Miller <justdave@syndicomm.com>
#                 Christopher Aillon <christopher@aillon.com>
#                 Myk Melez <myk@mozilla.org>
#                 Jeff Hedlund <jeff.hedlund@matrixsi.com>
#                 Frédéric Buclin <LpSolit@gmail.com>
#                 Lance Larsh <lance.larsh@oracle.com>
#                 Akamai Technologies <bugzilla-dev@akamai.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>

# Implementation notes for this file:
#
# 1) the 'id' form parameter is validated early on, and if it is not a valid
# bugid an error will be reported, so it is OK for later code to simply check
# for a defined form 'id' value, and it can assume a valid bugid.
#
# 2) If the 'id' form parameter is not defined (after the initial validation),
# then we are processing multiple bugs, and @idlist will contain the ids.
#
# 3) If we are processing just the one id, then it is stored in @idlist for
# later processing.

use strict;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Bug;
use Bugzilla::BugMail;
use Bugzilla::Mailer;
use Bugzilla::User;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Product;
use Bugzilla::Component;
use Bugzilla::Keyword;
use Bugzilla::Flag;
use Bugzilla::Status;

use Storable qw(dclone);

my $user = Bugzilla->login(LOGIN_REQUIRED);
local our $whoid = $user->id;
my $grouplist = $user->groups_as_string;

my $cgi = Bugzilla->cgi;
my $dbh = Bugzilla->dbh;
my $template = Bugzilla->template;
local our $vars = {};
$vars->{'valid_keywords'} = [map($_->name, Bugzilla::Keyword->get_all)];
$vars->{'use_keywords'} = 1 if Bugzilla::Keyword::keyword_count();

my @editable_bug_fields = editable_bug_fields();

local our $PrivilegesRequired = 0;

######################################################################
# Subroutines
######################################################################

# Used to send email when an update is done.
sub send_results {
    my ($bug_id, $vars) = @_;
    my $template = Bugzilla->template;
    if (Bugzilla->usage_mode == USAGE_MODE_EMAIL) {
         Bugzilla::BugMail::Send($bug_id, $vars->{'mailrecipients'});
    }
    else {
        $template->process("bug/process/results.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
    }
    $vars->{'header_done'} = 1;
}

# Tells us whether or not a field should be changed by process_bug, by
# checking that it's defined and not set to dontchange.
sub should_set {
    # check_defined is used for fields where there's another field
    # whose name starts with "defined_" and then the field name--it's used
    # to know when we did things like empty a multi-select or deselect
    # a checkbox.
    my ($field, $check_defined) = @_;
    my $cgi = Bugzilla->cgi;
    if (( defined $cgi->param($field) 
          || ($check_defined && defined $cgi->param("defined_$field")) )
        && ( !$cgi->param('dontchange') 
             || $cgi->param($field) ne $cgi->param('dontchange')) )
    {
        return 1;
    }
    return 0;
}

sub comment_exists {
    my $cgi = Bugzilla->cgi;
    return ($cgi->param('comment') && $cgi->param('comment') =~ /\S+/) ? 1 : 0;
}

######################################################################
# Begin Data/Security Validation
######################################################################

# Create a list of IDs of all bugs being modified in this request.
# This list will either consist of a single bug number from the "id"
# form/URL field or a series of numbers from multiple form/URL fields
# named "id_x" where "x" is the bug number.
# For each bug being modified, make sure its ID is a valid bug number 
# representing an existing bug that the user is authorized to access.
my (@idlist, @bug_objects);
if (defined $cgi->param('id')) {
  my $id = $cgi->param('id');
  ValidateBugID($id);

  # Store the validated, and detainted id back in the cgi data, as
  # lots of later code will need it, and will obtain it from there
  $cgi->param('id', $id);
  push @idlist, $id;
  push(@bug_objects, new Bugzilla::Bug($id));
} else {
    foreach my $i ($cgi->param()) {
        if ($i =~ /^id_([1-9][0-9]*)/) {
            my $id = $1;
            ValidateBugID($id);
            push @idlist, $id;
            # We do this until we have Bugzilla::Bug->new_from_list.
            push(@bug_objects, new Bugzilla::Bug($id));
        }
    }
}

# Make sure there are bugs to process.
scalar(@idlist) || ThrowUserError("no_bugs_chosen", {action => 'modify'});

# Build a bug object using the first bug id, for validations.
my $bug = $bug_objects[0];

# Make sure form param 'dontchange' is defined so it can be compared to easily.
$cgi->param('dontchange','') unless defined $cgi->param('dontchange');

# Make sure the 'knob' param is defined; else set it to 'none'.
$cgi->param('knob', 'none') unless defined $cgi->param('knob');

$cgi->param('comment', $bug->_check_comment($cgi->param('comment')));

# If the bug(s) being modified have dependencies, validate them
# and rebuild the list with the validated values.  This is important
# because there are situations where validation changes the value
# instead of throwing an error, f.e. when one or more of the values
# is a bug alias that gets converted to its corresponding bug ID
# during validation.
if ($cgi->param('id') && (defined $cgi->param('dependson')
                          || defined $cgi->param('blocked')) )
{
    $bug->set_dependencies(scalar $cgi->param('dependson'),
                           scalar $cgi->param('blocked'));
}
# Right now, you can't modify dependencies on a mass change.
else {
    $cgi->delete('dependson');
    $cgi->delete('blocked');
}

# do a match on the fields if applicable

# The order of these function calls is important, as Flag::validate
# assumes User::match_field has ensured that the values
# in the requestee fields are legitimate user email addresses.
&Bugzilla::User::match_field($cgi, {
    'qa_contact'                => { 'type' => 'single' },
    'newcc'                     => { 'type' => 'multi'  },
    'masscc'                    => { 'type' => 'multi'  },
    'assigned_to'               => { 'type' => 'single' },
    '^requestee(_type)?-(\d+)$' => { 'type' => 'multi'  },
});

# Validate flags in all cases. validate() should not detect any
# reference to flags if $cgi->param('id') is undefined.
Bugzilla::Flag::validate($cgi, $cgi->param('id'));

######################################################################
# End Data/Security Validation
######################################################################

print $cgi->header() unless Bugzilla->usage_mode == USAGE_MODE_EMAIL;
$vars->{'title_tag'} = "bug_processed";

# Set the title if we can see a mid-air coming. This test may have false
# negatives, but never false positives, and should catch the majority of cases.
# It only works at all in the single bug case.
if (defined $cgi->param('id')) {
    if (defined $cgi->param('delta_ts')
        && $cgi->param('delta_ts') ne $bug->delta_ts)
    {
        $vars->{'title_tag'} = "mid_air";
        ThrowCodeError('undefined_field', {field => 'longdesclength'})
          if !defined $cgi->param('longdesclength');
    }
}

# Set up the vars for navigational <link> elements
my @bug_list;
if ($cgi->cookie("BUGLIST") && defined $cgi->param('id')) {
    @bug_list = split(/:/, $cgi->cookie("BUGLIST"));
    $vars->{'bug_list'} = \@bug_list;
}

my $product_change; # XXX Temporary until all of process_bug uses update()
if (should_set('product')) {
    # We only pass the fields if they're defined and not set to dontchange.
    # This is because when you haven't changed the product, --do-not-change--
    # isn't a valid component, version, or target_milestone. (When you're
    # doing a mass-change, some bugs might already be in the new product.)
    my %product_fields;
    foreach my $field (qw(component version target_milestone)) {
        if (should_set($field)) {
            $product_fields{$field} = $cgi->param($field);
        }
    }

    foreach my $b (@bug_objects) {
        my $changed = $b->set_product(scalar $cgi->param('product'),
            { %product_fields,
              change_confirmed => scalar $cgi->param('confirm_product_change'),
              other_bugs => \@bug_objects,
            });
        $product_change ||= $changed;
        
        # strict_isolation checks mean that we should set the groups
        # immediately after changing the product.
        foreach my $group (@{$b->product_obj->groups_valid}) {
            my $gid = $group->id;
            if (should_set("bit-$gid", 1)) {
                # Check ! first to avoid having to check defined below.
                if (!$cgi->param("bit-$gid")) {
                    $b->remove_group($gid);
                }
                # "== 1" is important because mass-change uses -1 to mean
                # "don't change this restriction"
                elsif ($cgi->param("bit-$gid") == 1) {
                    $b->add_group($gid);
                }
            }
        }
    }
}

# Component, target_milestone, and version are in here just in case
# the 'product' field wasn't defined in the CGI. It doesn't hurt to set
# them twice.
my @set_fields = qw(op_sys rep_platform priority bug_severity
                    component target_milestone version
                    bug_file_loc status_whiteboard short_desc
                    deadline remaining_time estimated_time);
push(@set_fields, 'assigned_to') if !$cgi->param('set_default_assignee');
push(@set_fields, 'qa_contact')  if !$cgi->param('set_default_qa_contact');

my %methods = (
    bug_severity => 'set_severity',
    rep_platform => 'set_platform',
    short_desc   => 'set_summary',
    bug_file_loc => 'set_url',
);
foreach my $b (@bug_objects) {
    if (should_set('comment') || $cgi->param('work_time')) {
        # Add a comment as needed to each bug. This is done early because
        # there are lots of things that want to check if we added a comment.
        $b->add_comment(scalar($cgi->param('comment')),
            { isprivate => scalar $cgi->param('commentprivacy'),
              work_time => scalar $cgi->param('work_time') });
    }
    foreach my $field_name (@set_fields) {
        if (should_set($field_name)) {
            my $method = $methods{$field_name};
            $method ||= "set_" . $field_name;
            $b->$method($cgi->param($field_name));
        }
    }
    $b->reset_assigned_to if $cgi->param('set_default_assignee');
    $b->reset_qa_contact  if $cgi->param('set_default_qa_contact');
}

my $action = trim($cgi->param('action') || '');

$::query = "UPDATE bugs SET";
$::comma = "";
local our @values;
umask(0);

sub DoComma {
    $::query .= "$::comma\n    ";
    $::comma = ",";
}

# Add custom fields data to the query that will update the database.
foreach my $field (Bugzilla->get_fields({custom => 1, obsolete => 0})) {
    my $fname = $field->name;
    if (should_set($fname, 1)) {
        $_->set_custom_field($field, [$cgi->param($fname)]) foreach @bug_objects;
    }
}

my ($product, @newprod_ids);
if ($cgi->param('product') ne $cgi->param('dontchange')) {
    $product = Bugzilla::Product::check_product(scalar $cgi->param('product'));
    @newprod_ids = ($product->id);
} else {
    @newprod_ids = @{$dbh->selectcol_arrayref(
        "SELECT DISTINCT product_id FROM bugs WHERE " 
        . $dbh->sql_in('bug_id', \@idlist))};
    if (scalar(@newprod_ids) == 1) {
        $product = new Bugzilla::Product($newprod_ids[0]);
    }
}

my (@cc_add, @cc_remove);

# Certain changes can only happen on individual bugs, never on mass-changes.
if (defined $cgi->param('id')) {
    my $bug = $bug_objects[0];
    
    # Since aliases are unique (like bug numbers), they can only be changed
    # for one bug at a time.
    if (Bugzilla->params->{"usebugaliases"} && defined $cgi->param('alias')) {
        $bug->set_alias($cgi->param('alias'));
    }

    # reporter_accessible and cclist_accessible--these are only set if
    # the user can change them and they appear on the page.
    if (should_set('cclist_accessible', 1)) {
        $bug->set_cclist_accessible($cgi->param('cclist_accessible'))
    }
    if (should_set('reporter_accessible', 1)) {
        $bug->set_reporter_accessible($cgi->param('reporter_accessible'))
    }
    
    # You can only mark/unmark comments as private on single bugs. If
    # you're not in the insider group, this code won't do anything.
    foreach my $field (grep(/^defined_isprivate/, $cgi->param())) {
        $field =~ /(\d+)$/;
        my $comment_id = $1;
        $bug->set_comment_is_private($comment_id,
                                     $cgi->param("isprivate_$comment_id"));
    }
}

# We need to check the addresses involved in a CC change before we touch 
# any bugs. What we'll do here is formulate the CC data into two arrays of
# users involved in this CC change.  Then those arrays can be used later 
# on for the actual change.
if (defined $cgi->param('newcc')
    || defined $cgi->param('addselfcc')
    || defined $cgi->param('removecc')
    || defined $cgi->param('masscc')) {
        
    # If masscc is defined, then we came from buglist and need to either add or
    # remove cc's... otherwise, we came from bugform and may need to do both.
    my ($cc_add, $cc_remove) = "";
    if (defined $cgi->param('masscc')) {
        if ($cgi->param('ccaction') eq 'add') {
            $cc_add = join(' ',$cgi->param('masscc'));
        } elsif ($cgi->param('ccaction') eq 'remove') {
            $cc_remove = join(' ',$cgi->param('masscc'));
        }
    } else {
        $cc_add = join(' ',$cgi->param('newcc'));
        # We came from bug_form which uses a select box to determine what cc's
        # need to be removed...
        if (defined $cgi->param('removecc') && $cgi->param('cc')) {
            $cc_remove = join (",", $cgi->param('cc'));
        }
    }

    push(@cc_add, split(/[\s,]+/, $cc_add)) if $cc_add;
    push(@cc_add, Bugzilla->user) if $cgi->param('addselfcc');

    push(@cc_remove, split(/[\s,]+/, $cc_remove)) if $cc_remove;
}

foreach my $b (@bug_objects) {
    $b->remove_cc($_) foreach @cc_remove;
    $b->add_cc($_) foreach @cc_add;
    # Theoretically you could move a product without ever specifying
    # a new assignee or qa_contact, or adding/removing any CCs. So,
    # we have to check that the current assignee, qa, and CCs are still
    # valid if we've switched products, under strict_isolation. We can only
    # do that here. There ought to be some better way to do this,
    # architecturally, but I haven't come up with it.
    if ($product_change) {
        $b->_check_strict_isolation();
    }
}

if ($action eq Bugzilla->params->{'move-button-text'}) {
    Bugzilla->params->{'move-enabled'} || ThrowUserError("move_bugs_disabled");

    $user->is_mover || ThrowUserError("auth_failure", {action => 'move',
                                                       object => 'bugs'});

    my @multi_select_locks  = map {'bug_' . $_->name . " WRITE"}
        Bugzilla->get_fields({ custom => 1, type => FIELD_TYPE_MULTI_SELECT,
                               obsolete => 0 });

    $dbh->bz_lock_tables('bugs WRITE', 'bugs_activity WRITE', 'duplicates WRITE',
                         'longdescs WRITE', 'profiles READ', 'groups READ',
                         'bug_group_map READ', 'group_group_map READ',
                         'user_group_map READ', 'classifications READ',
                         'products READ', 'components READ', 'votes READ',
                         'cc READ', 'fielddefs READ', 'bug_status READ',
                         'status_workflow READ', 'resolution READ', @multi_select_locks);

    # First update all moved bugs.
    foreach my $bug (@bug_objects) {
        $bug->add_comment(scalar $cgi->param('comment'),
                          { type => CMT_MOVED_TO, extra_data => $user->login });
    }
    # Don't export the new status and resolution. We want the current ones.
    local $Storable::forgive_me = 1;
    my $bugs = dclone(\@bug_objects);
    foreach my $bug (@bug_objects) {
        my ($status, $resolution) = $bug->get_new_status_and_resolution('move');
        $bug->set_status($status);
        # We don't use set_resolution here because the MOVED resolution is
        # special and is normally rejected by set_resolution.
        $bug->{resolution} = $resolution;
        # That means that we need to clear dups manually. Eventually this
        # bug-moving code will all be inside Bugzilla::Bug, so it's OK
        # to call an internal function here.
        $bug->_clear_dup_id;
    }
    $_->update() foreach @bug_objects;
    $dbh->bz_unlock_tables();

    # Now send emails.
    foreach my $id (@idlist) {
        $vars->{'mailrecipients'} = { 'changer' => $user->login };
        $vars->{'id'} = $id;
        $vars->{'type'} = "move";
        send_results($id, $vars);
    }
    # Prepare and send all data about these bugs to the new database
    my $to = Bugzilla->params->{'move-to-address'};
    $to =~ s/@/\@/;
    my $from = Bugzilla->params->{'moved-from-address'};
    $from =~ s/@/\@/;
    my $msg = "To: $to\n";
    $msg .= "From: Bugzilla <" . $from . ">\n";
    $msg .= "Subject: Moving bug(s) " . join(', ', @idlist) . "\n\n";

    my @fieldlist = (Bugzilla::Bug->fields, 'group', 'long_desc',
                     'attachment', 'attachmentdata');
    my %displayfields;
    foreach (@fieldlist) {
        $displayfields{$_} = 1;
    }

    $template->process("bug/show.xml.tmpl", { bugs => $bugs,
                                              displayfields => \%displayfields,
                                            }, \$msg)
      || ThrowTemplateError($template->error());

    $msg .= "\n";
    MessageToMTA($msg);

    # End the response page.
    unless (Bugzilla->usage_mode == USAGE_MODE_EMAIL) {
        $template->process("bug/navigate.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
        $template->process("global/footer.html.tmpl", $vars)
            || ThrowTemplateError($template->error());
    }
    exit;
}


# You cannot mark bugs as duplicates when changing several bugs at once
# (because currently there is no way to check for duplicate loops in that
# situation).
if (!$cgi->param('id') && $cgi->param('dup_id')) {
    ThrowUserError('dupe_not_allowed');
}

# Set the status, resolution, and dupe_of (if needed). This has to be done
# down here, because the validity of status changes depends on other fields,
# such as Target Milestone.
foreach my $b (@bug_objects) {
    if (should_set('knob')) {
        # First, get the correct resolution <select>, in case there is more
        # than one open -> closed transition allowed.
        my $knob = $cgi->param('knob');
        my $status = new Bugzilla::Status({name => $knob});
        my $resolution;
        if ($status) {
            $resolution = $cgi->param('resolution_knob_' . $status->id);
        }
        else {
            $resolution = $cgi->param('resolution_knob_change_resolution');
        }
        
        # Translate the knob values into new status and resolution values.
        $b->process_knob($knob, $resolution, scalar $cgi->param('dup_id'));
    }
}

my $any_keyword_changes;
if (defined $cgi->param('keywords')) {
    foreach my $b (@bug_objects) {
        my $return =
            $b->modify_keywords(scalar $cgi->param('keywords'),
                                scalar $cgi->param('keywordaction'));
        $any_keyword_changes ||= $return;
    }
}

if ($::comma eq ""
    && !$any_keyword_changes
    && defined $cgi->param('masscc') && ! $cgi->param('masscc')
    ) {
    if (!defined $cgi->param('comment') || $cgi->param('comment') =~ /^\s*$/) {
        ThrowUserError("bugs_not_changed");
    }
}

my $basequery = $::query;

local our $delta_ts;
sub SnapShotBug {
    my ($id) = (@_);
    my $dbh = Bugzilla->dbh;
    my @row = $dbh->selectrow_array(q{SELECT delta_ts, } .
                join(',', editable_bug_fields()).q{ FROM bugs WHERE bug_id = ?},
                undef, $id);
    $delta_ts = shift @row;

    return @row;
}

my $timestamp;

my %bug_objects = map {$_->id => $_} @bug_objects;

# This loop iterates once for each bug to be processed (i.e. all the
# bugs selected when this script is called with multiple bugs selected
# from buglist.cgi, or just the one bug when called from
# show_bug.cgi).
#
foreach my $id (@idlist) {
    my $query = $basequery;
    my @bug_values = @values;
    # XXX We really have to get rid of $::comma.
    my $comma = $::comma;
    my $old_bug_obj = new Bugzilla::Bug($id);

    my $bug_changed = 0;
    my $write = "WRITE";        # Might want to make a param to control
                                # whether we do LOW_PRIORITY ...

    my @multi_select_locks  = map {'bug_' . $_->name . " $write"}
        Bugzilla->get_fields({ custom => 1, type => FIELD_TYPE_MULTI_SELECT,
                               obsolete => 0 });

    $dbh->bz_lock_tables("bugs $write", "bugs_activity $write", "cc $write",
            "profiles READ", "dependencies $write", "votes $write",
            "products READ", "components READ", "milestones READ",
            "keywords $write", "longdescs $write", "fielddefs READ",
            "bug_group_map $write", "flags $write", "duplicates $write",
            "user_group_map READ", "group_group_map READ", "flagtypes READ",
            "flaginclusions AS i READ", "flagexclusions AS e READ",
            "keyworddefs READ", "groups READ", "attachments READ",
            "bug_status READ", "group_control_map AS oldcontrolmap READ",
            "group_control_map AS newcontrolmap READ",
            "group_control_map READ", "email_setting READ", 
            "classifications READ", @multi_select_locks);

    # It may sound crazy to set %formhash for each bug as $cgi->param()
    # will not change, but %formhash is modified below and we prefer
    # to set it again.
    my $i = 0;
    my @oldvalues = SnapShotBug($id);
    my %oldhash;
    my %formhash;
    foreach my $col (@editable_bug_fields) {
        # Consider NULL db entries to be equivalent to the empty string
        $oldvalues[$i] = defined($oldvalues[$i]) ? $oldvalues[$i] : '';
        # Convert the deadline taken from the DB into the YYYY-MM-DD format
        # for consistency with the deadline provided by the user, if any.
        # Else Bug::check_can_change_field() would see them as different
        # in all cases.
        if ($col eq 'deadline') {
            $oldvalues[$i] = format_time($oldvalues[$i], "%Y-%m-%d");
        }
        $oldhash{$col} = $oldvalues[$i];
        $formhash{$col} = $cgi->param($col) if defined $cgi->param($col);
        $i++;
    }

    # This hash is required by Bug::check_can_change_field().
    my $cgi_hash = {'dontchange' => scalar $cgi->param('dontchange')};
    foreach my $col (@editable_bug_fields) {
        # XXX - Ugly workaround which has to go away before 3.1.3.
        next if ($col eq 'assigned_to' || $col eq 'qa_contact');
        if (exists $formhash{$col}
            && !$old_bug_obj->check_can_change_field($col, $oldhash{$col}, $formhash{$col},
                                                     \$PrivilegesRequired, $cgi_hash))
        {
            my $vars;
            if ($col eq 'component_id') {
                # Display the component name
                $vars->{'oldvalue'} = $old_bug_obj->component;
                $vars->{'newvalue'} = $cgi->param('component');
                $vars->{'field'} = 'component';
            } else {
                $vars->{'oldvalue'} = $oldhash{$col};
                $vars->{'newvalue'} = $formhash{$col};
                $vars->{'field'} = $col;
            }
            $vars->{'privs'} = $PrivilegesRequired;
            ThrowUserError("illegal_change", $vars);
        }
    }
    
    $oldhash{'product'} = $old_bug_obj->product;
    if (!Bugzilla->user->can_edit_product($oldhash{'product_id'})) {
        ThrowUserError("product_edit_denied",
                      { product => $oldhash{'product'} });
    }

    my $new_product = $bug_objects{$id}->product_obj;

    if (defined $cgi->param('delta_ts') && $cgi->param('delta_ts') ne $delta_ts)
    {
        ($vars->{'operations'}) =
            Bugzilla::Bug::GetBugActivity($id, undef, $cgi->param('delta_ts'));

        $vars->{'start_at'} = $cgi->param('longdesclength');

        # Always sort midair collision comments oldest to newest,
        # regardless of the user's personal preference.
        $vars->{'comments'} = Bugzilla::Bug::GetComments($id, "oldest_to_newest");

        $cgi->param('delta_ts', $delta_ts);
        
        $vars->{'bug_id'} = $id;
        
        $dbh->bz_unlock_tables(UNLOCK_ABORT);
        
        # Warn the user about the mid-air collision and ask them what to do.
        $template->process("bug/process/midair.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
        exit;
    }

   
    #################################
    # Start Actual Database Updates #
    #################################
    
    $timestamp = $dbh->selectrow_array(q{SELECT NOW()});

    my $changes = $bug_objects{$id}->update($timestamp);

    my %notify_deps;
    if ($changes->{'bug_status'}) {
        my ($old_status, $new_status) = @{ $changes->{'bug_status'} };
        
        # If this bug has changed from opened to closed or vice-versa,
        # then all of the bugs we block need to be notified.
        if (is_open_state($old_status) ne is_open_state($new_status)) {
            $notify_deps{$_} = 1 foreach (@{$bug_objects{$id}->blocked});
        }
        
        # We may have zeroed the remaining time, if we moved into a closed
        # status, so we should inform the user about that.
        if (!is_open_state($new_status) && $changes->{'remaining_time'}) {
            $vars->{'message'} = "remaining_time_zeroed"
              if Bugzilla->user->in_group(Bugzilla->params->{'timetrackinggroup'});
        }
    }

    $bug_objects{$id}->update_keywords($timestamp);
    
    $query .= " WHERE bug_id = ?";
    push(@bug_values, $id);

    if ($comma ne '') {
        $dbh->do($query, undef, @bug_values);
    }

    my ($cc_removed) = $bug_objects{$id}->update_cc($timestamp);
    $cc_removed = [map {$_->login} @$cc_removed];

    my ($dep_changes) = $bug_objects{$id}->update_dependencies($timestamp);
    
    # Convert the "changes" hash into a list of all the bug ids, then
    # convert that into a hash to eliminate duplicates. ("map {@$_}" collapses
    # an array of arrays.)
    my @all_changed_deps = map { @$_ } @{$dep_changes->{'dependson'}};
    push(@all_changed_deps, map { @$_ } @{$dep_changes->{'blocked'}});
    my %changed_deps = map { $_ => 1 } @all_changed_deps;

    # get a snapshot of the newly set values out of the database,
    # and then generate any necessary bug activity entries by seeing 
    # what has changed since before we wrote out the new values.
    #
    my $new_bug_obj = new Bugzilla::Bug($id);
    my @newvalues = SnapShotBug($id);
    my %newhash;
    $i = 0;
    foreach my $col (@editable_bug_fields) {
        # Consider NULL db entries to be equivalent to the empty string
        $newvalues[$i] = defined($newvalues[$i]) ? $newvalues[$i] : '';
        # Convert the deadline to the YYYY-MM-DD format.
        if ($col eq 'deadline') {
            $newvalues[$i] = format_time($newvalues[$i], "%Y-%m-%d");
        }
        $newhash{$col} = $newvalues[$i];
        $i++;
    }

    # $msgs will store emails which have to be sent to voters, if any.
    my $msgs;
    
    foreach my $c (@editable_bug_fields) {
        my $col = $c;           # We modify it, don't want to modify array
                                # values in place.
        my $old = shift @oldvalues;
        my $new = shift @newvalues;
        if ($old ne $new) {

            # Bugzilla::Bug does these for us already.
            next if grep($_ eq $col, qw(keywords op_sys rep_platform priority
                                        product_id component_id version
                                        target_milestone assigned_to qa_contact
                                        bug_severity short_desc alias
                                        deadline estimated_time remaining_time
                                        reporter_accessible cclist_accessible
                                        bug_status resolution
                                        status_whiteboard bug_file_loc),
                                     Bugzilla->custom_field_names);

            if ($col eq 'product') {
                # If some votes have been removed, RemoveVotes() returns
                # a list of messages to send to voters.
                # We delay the sending of these messages till tables are unlocked.
                $msgs = RemoveVotes($id, 0,
                          "This bug has been moved to a different product");

                CheckIfVotedConfirmed($id, $whoid);
            }

            LogActivityEntry($id,$col,$old,$new,$whoid,$timestamp);
            $bug_changed = 1;
        }
    }
    # Set and update flags.
    Bugzilla::Flag::process($new_bug_obj, undef, $timestamp, $cgi, $vars);

    if ($bug_changed) {
        $dbh->do(q{UPDATE bugs SET delta_ts = ? WHERE bug_id = ?},
                 undef, $timestamp, $id);
    }
    $dbh->bz_unlock_tables();

    # Now is a good time to send email to voters.
    foreach my $msg (@$msgs) {
        MessageToMTA($msg);
    }

    # Now all changes to the DB have been made. It's time to email
    # all concerned users, including the bug itself, but also the
    # duplicated bug and dependent bugs, if any.

    my $orig_qa = $old_bug_obj->qa_contact;
    $vars->{'mailrecipients'} = {
        cc        => $cc_removed,
        owner     => $old_bug_obj->assigned_to->login,
        qacontact => $orig_qa ? $orig_qa->login : '',
        changer   => Bugzilla->user->login };

    $vars->{'id'} = $id;
    $vars->{'type'} = "bug";
    
    # Let the user know the bug was changed and who did and didn't
    # receive email about the change.
    send_results($id, $vars);
 
    # If the bug was marked as a duplicate, we need to notify users on the
    # other bug of any changes to that bug.
    my $new_dup_id = $changes->{'dup_id'} ? $changes->{'dup_id'}->[1] : undef;
    if ($new_dup_id) {
        $vars->{'mailrecipients'} = { 'changer' => Bugzilla->user->login }; 

        $vars->{'id'} = $new_dup_id;
        $vars->{'type'} = "dupe";
        
        # Let the user know a duplication notation was added to the 
        # original bug.
        send_results($new_dup_id, $vars);
    }

    my %all_dep_changes = (%notify_deps, %changed_deps);
    foreach my $id (sort { $a <=> $b } (keys %all_dep_changes)) {
        $vars->{'mailrecipients'} = { 'changer' => Bugzilla->user->login };
        $vars->{'id'} = $id;
        $vars->{'type'} = "dep";

        # Let the user (if he is able to see the bug) know we checked to
        # see if we should email notice of this change to users with a 
        # relationship to the dependent bug and who did and didn't 
        # receive email about it.
        send_results($id, $vars);
    }
}

# Determine if Patch Viewer is installed, for Diff link
# (NB: Duplicate code with show_bug.cgi.)
eval {
    require PatchReader;
    $vars->{'patchviewerinstalled'} = 1;
};

if (defined $cgi->param('id')) {
    $action = Bugzilla->user->settings->{'post_bug_submit_action'}->{'value'};
} else {
    # param('id') is not defined when changing multiple bugs
    $action = 'nothing';
}

if (Bugzilla->usage_mode == USAGE_MODE_EMAIL) {
    # Do nothing.
}
elsif ($action eq 'next_bug') {
    my $next_bug;
    my $cur = lsearch(\@bug_list, $cgi->param("id"));
    if ($cur >= 0 && $cur < $#bug_list) {
        $next_bug = $bug_list[$cur + 1];
    }
    if ($next_bug) {
        if (detaint_natural($next_bug) && Bugzilla->user->can_see_bug($next_bug)) {
            my $bug = new Bugzilla::Bug($next_bug);
            ThrowCodeError("bug_error", { bug => $bug }) if $bug->error;

            $vars->{'bugs'} = [$bug];
            $vars->{'nextbug'} = $bug->bug_id;

            $template->process("bug/show.html.tmpl", $vars)
              || ThrowTemplateError($template->error());

            exit;
        }
    }
} elsif ($action eq 'same_bug') {
    if (Bugzilla->user->can_see_bug($cgi->param('id'))) {
        my $bug = new Bugzilla::Bug($cgi->param('id'));
        ThrowCodeError("bug_error", { bug => $bug }) if $bug->error;

        $vars->{'bugs'} = [$bug];

        $template->process("bug/show.html.tmpl", $vars)
          || ThrowTemplateError($template->error());

        exit;
    }
} elsif ($action ne 'nothing') {
    ThrowCodeError("invalid_post_bug_submit_action");
}

# End the response page.
unless (Bugzilla->usage_mode == USAGE_MODE_EMAIL) {
    # The user pref is 'Do nothing', so all we need is the current bug ID.
    $vars->{'bug'} = {bug_id => scalar $cgi->param('id')};

    $template->process("bug/navigate.html.tmpl", $vars)
        || ThrowTemplateError($template->error());
    $template->process("global/footer.html.tmpl", $vars)
        || ThrowTemplateError($template->error());
}

1;
