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
# The Original Code are the Bugzilla tests.
#
# The Initial Developer of the Original Code is Jacob Steenhagen.
# Portions created by Jacob Steenhagen are
# Copyright (C) 2001 Jacob Steenhagen. All
# Rights Reserved.
#
# Contributor(s): Gervase Markham <gerv@gerv.net>

# Important! The following classes of directives are excluded in the test,
# and so do not need to be added here. Doing so will cause warnings.
# See 008filter.t for more details.
#
# Comments                        - [%#...
# Directives                      - [% IF|ELSE|UNLESS|FOREACH...
# Assignments                     - [% foo = ...
# Simple literals                 - [% " selected" ...
# Values always used for numbers  - [% (i|j|k|n|count) %]
# Params                          - [% Param(...
# Safe functions                  - [% (time2str|GetBugLink)...
# Safe vmethods                   - [% foo.size %]
# TT loop variables               - [% loop.count %]
# Already-filtered stuff          - [% wibble FILTER html %]
#   where the filter is one of html|csv|js|url_quote|quoteUrls|time|uri|xml

# Key:
#
# "#": directive should be filtered, but not doing so is not a security hole
# The plan is to come back and add filtering for all those marked "#" after
# the security release.
#
# "# Email": as above; but noting that it's an email address.
# Other sorts of comments denote cleanups noticed while doing this work;
# they should be fixed in the very short term.

%::safe = (

'sidebar.xul.tmpl' => [
  'template_version', 
],

'search/boolean-charts.html.tmpl' => [
  '"field${chartnum}-${rownum}-${colnum}"',
  '"value${chartnum}-${rownum}-${colnum}"',
  '"type${chartnum}-${rownum}-${colnum}"',
  'field.name',
  'field.description',
  'type.name',
  'type.description',
  '"${chartnum}-${rownum}-${newor}"',
  '"${chartnum}-${newand}-0"',
  'newchart',
  '$jsmagic', #
],

'search/form.html.tmpl' => [
  'qv.value',
  'qv.name',
  'qv.description',
  'field.name',
  'field.description',
  'sel.name',
  'button_name', #
],

'search/knob.html.tmpl' => [
  'button_name', #
],

'reports/components.html.tmpl' => [
  'numcols',
  'numcols - 1',
  'comp.description',
  'comp.initialowner', # email address
  'comp.initialqacontact', # email address
],

'reports/duplicates-simple.html.tmpl' => [
  'title', #
],

'reports/duplicates-table.html.tmpl' => [
  '"&maxrows=$maxrows" IF maxrows',
  '"&changedsince=$changedsince" IF changedsince',
  '"&product=$product" IF product', #
  '"&format=$format" IF format', #
  '"&bug_id=$bug_ids_string&sortvisible=1" IF sortvisible',
  'column.name',
  'column.description',
  'vis_bug_ids.push(bug.id)',
  'bug.id',
  'bug.count',
  'bug.delta',
  'bug.component', #
  'bug.bug_severity', #
  'bug.op_sys', #
  'bug.target_milestone', #
],

'reports/duplicates.html.tmpl' => [
  'bug_ids_string',
  'maxrows',
  'changedsince',
  'reverse',
],

'reports/keywords.html.tmpl' => [
  'keyword.description',
  'keyword.bugcount',
],

'list/change-columns.html.tmpl' => [
  'column',
  'desc.${column}', #
],

'list/edit-multiple.html.tmpl' => [
  'group.bit',
  'group.description',
  'group.description FILTER strike',
  'knum',
  'menuname',
  'selected IF resolution == "FIXED"', #
],

'list/list-rdf.rdf.tmpl' => [
  'template_version',
  'bug.id',
  'column',
],

'list/list-simple.html.tmpl' => [
  'title',
],

'list/list.html.tmpl' => [
  'currenttime', #
  'buglist',
  'bugowners', # email address
],

'list/table.html.tmpl' => [
  'id',
  'splitheader ? 2 : 1',
  'abbrev.$id.title || column.title', #
  'tableheader',
  'bug.severity', #
  'bug.priority', #
  'bug.id',
],

'global/choose-product.html.tmpl' => [
  'target',
  'proddesc.$p',
],

'global/code-error.html.tmpl' => [
  'error',
],

'global/footer.html.tmpl' => [
  'CALL SyncAnyPendingShadowChanges() IF SyncAnyPendingShadowChanges',
],

'global/header.html.tmpl' => [
  'header_html',
  'javascript',
  'style',
  'style_url',
  'bgcolor',
  'onload',
  'h1',
  'h2',
  'message',
],

'global/hidden-fields.html.tmpl' => [
  'mvalue | html | html_linebreak', # Need to eliminate | usage
  'field.value | html | html_linebreak',
],

'global/select-menu.html.tmpl' => [
  'options', 
],

'global/useful-links.html.tmpl' => [
  'user.login', # Email address
],

'global/user-error.html.tmpl' => [
  'error', # can contain HTML in 2.16.x
],

'bug/comments.html.tmpl' => [
  'comment.time',
  'quoteUrls(comment.body)',
],

'bug/dependency-graph.html.tmpl' => [
  'image_map', # We need to continue to make sure this is safe in the CGI
  'image_url', 
  'map_url', 
  'bug_id', 
],

'bug/dependency-tree.html.tmpl' => [
  'hide_resolved ? "Open b" : "B"', 
  'bugid', 
  'maxdepth', 
  'dependson_ids.join(",")', 
  'blocked_ids.join(",")',
  'dep_id',
  'hide_resolved ? 0 : 1',
  'hide_resolved ? "Show" : "Hide"',
  'realdepth < 2 || maxdepth == 1 ? "disabled" : ""',
  'hide_resolved',
  'realdepth < 2 ? "disabled" : ""',
  'maxdepth + 1',
  'maxdepth == 0 || maxdepth == realdepth ? "disabled" : ""',
  'realdepth < 2 || ( maxdepth && maxdepth < 2 ) ? "disabled" : ""',
  'maxdepth > 0 && maxdepth <= realdepth ? maxdepth : ""',
  'maxdepth == 1 ? 1 
                       : ( maxdepth ? maxdepth - 1 : realdepth - 1 )',
  'realdepth < 2 || ! maxdepth || maxdepth >= realdepth ?
            "disabled" : ""',
],

'bug/edit.html.tmpl' => [
  'bug.delta_ts',
  'bug.bug_id',
  'bug.votes',
  'group.bit',
  'group.description',
  'knum',
  'dep.title',
  'dep.fieldname',
  'bug.${dep.fieldname}.join(\', \')',
  'selname',
  'bug.longdesclength',
  'bug.creation_ts',
],

'bug/navigate.html.tmpl' => [
  'this_bug_idx + 1',
  'bug_list.first',
  'bug_list.last',
  'bug_list.$prev_bug',
  'bug_list.$next_bug',
],

'bug/show-multiple.html.tmpl' => [
  'bug.bug_id',
  'bug.component', #
  'attr.description', #
],

'bug/votes/list-for-bug.html.tmpl' => [
  'voter.count',
  'total',
],

'bug/votes/list-for-user.html.tmpl' => [
  'product.maxperbug',
  'bug.id',
  'bug.count',
  'product.total',
  'product.maxvotes',
],
# h2 = voting_user.name # Email

'bug/process/confirm-duplicate.html.tmpl' => [
  'original_bug_id',
  'duplicate_bug_id',
],

'bug/process/midair.html.tmpl' => [
  'bug_id',
],

'bug/process/next.html.tmpl' => [
  'next_id',
],

'bug/process/results.html.tmpl' => [
  'title.$type',
  'id',
  'mail',
],

'bug/process/verify-new-product.html.tmpl' => [
  'form.product', # 
],

'bug/create/create.html.tmpl' => [
  'default.bug_status', #
  'g.bit',
  'g.description',
  'sel.name',
  'sel.description',
],

'bug/activity/show.html.tmpl' => [
  'bug_id',
],

'bug/activity/table.html.tmpl' => [
  'operation.who', # Email
  'operation.when',
  'change.attachid',
  'change.field',
],

'attachment/create.html.tmpl' => [
  'bugid',
  'attachment.id',
],

'attachment/created.html.tmpl' => [
  'attachid',
  'bugid',
  'contenttype',
  'mailresults',
],

'attachment/edit.html.tmpl' => [
  'attachid',
  'bugid',
  'def.id',
  'a',
],

'attachment/list.html.tmpl' => [
  'attachment.attachid',
  'attachment.date',
  'bugid',
],

'attachment/show-multiple.html.tmpl' => [
  'a.attachid',
  'a.date',
],

'attachment/updated.html.tmpl' => [
  'attachid',
  'bugid',
  'mailresults',
],

'admin/attachstatus/create.html.tmpl' => [
  'id',
],

'admin/attachstatus/delete.html.tmpl' => [
  'attachcount',
  'id',
  'name',
],

'admin/attachstatus/edit.html.tmpl' => [
  'id',
  'sortkey',
],

'admin/attachstatus/list.html.tmpl' => [
  'statusdef.sortkey',
  'statusdef.id',
  'statusdef.attachcount',
],

'account/prefs/account.html.tmpl' => [
  'login_change_date', #
],

'account/prefs/email.html.tmpl' => [
  'watchedusers', # Email
  '(useqacontact AND usevotes) ? \'5\' : ((useqacontact OR usevotes) ? \'4\' : \'3\')',
  'role',
  'reason.name',
  'reason.description',
],

'account/prefs/permissions.html.tmpl' => [
  'bit_description',
],

'account/prefs/prefs.html.tmpl' => [
  'tab.name',
  'tab.description',
  'changes_saved',
  'current_tab.name',
  'current_tab.description',
  'current_tab.description FILTER lower',
],

);
