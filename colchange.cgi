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
#                 Gervase Markham <gerv@gerv.net>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Pascal Held <paheld@gmail.com>

use strict;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::CGI;
use Bugzilla::Search::Saved;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Keyword;

Bugzilla->login();

my $cgi = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars = {};

# The master list not only says what fields are possible, but what order
# they get displayed in.
my @masterlist = ("opendate", "changeddate", "bug_severity", "priority",
                  "rep_platform", "assigned_to", "assigned_to_realname",
                  "reporter", "reporter_realname", "bug_status",
                  "resolution");

if (Bugzilla->params->{"useclassification"}) {
    push(@masterlist, "classification");
}

push(@masterlist, ("product", "component", "version", "op_sys"));

if (Bugzilla->params->{"usevotes"}) {
    push (@masterlist, "votes");
}
if (Bugzilla->params->{"usebugaliases"}) {
    unshift(@masterlist, "alias");
}
if (Bugzilla->params->{"usetargetmilestone"}) {
    push(@masterlist, "target_milestone");
}
if (Bugzilla->params->{"useqacontact"}) {
    push(@masterlist, "qa_contact");
    push(@masterlist, "qa_contact_realname");
}
if (Bugzilla->params->{"usestatuswhiteboard"}) {
    push(@masterlist, "status_whiteboard");
}
if (Bugzilla::Keyword->any_exist) {
    push(@masterlist, "keywords");
}
if (Bugzilla->has_flags) {
    push(@masterlist, "flagtypes.name");
}
if (Bugzilla->user->is_timetracker) {
    push(@masterlist, ("estimated_time", "remaining_time", "actual_time",
                       "percentage_complete", "deadline")); 
}

push(@masterlist, ("short_desc", "short_short_desc"));

my @custom_fields = grep { $_->type != FIELD_TYPE_MULTI_SELECT }
                         Bugzilla->active_custom_fields;
push(@masterlist, map { $_->name } @custom_fields);

Bugzilla::Hook::process('colchange_columns', {'columns' => \@masterlist} );

$vars->{'masterlist'} = \@masterlist;

my @collist;
if (defined $cgi->param('rememberedquery')) {
    my $splitheader = 0;
    if (defined $cgi->param('resetit')) {
        @collist = DEFAULT_COLUMN_LIST;
    } else {
        if (defined $cgi->param("selected_columns")) {
            my %legal_list = map { $_ => 1 } @masterlist;
            @collist = grep { exists $legal_list{$_} } $cgi->param("selected_columns");
        }
        if (defined $cgi->param('splitheader')) {
            $splitheader = $cgi->param('splitheader')? 1: 0;
        }
    }
    my $list = join(" ", @collist);

    if ($list) {
        # Only set the cookie if this is not a saved search.
        # Saved searches have their own column list
        if (!$cgi->param('save_columns_for_search')) {
            $cgi->send_cookie(-name => 'COLUMNLIST',
                              -value => $list,
                              -expires => 'Fri, 01-Jan-2038 00:00:00 GMT');
        }
    }
    else {
        $cgi->remove_cookie('COLUMNLIST');
    }
    if ($splitheader) {
        $cgi->send_cookie(-name => 'SPLITHEADER',
                          -value => $splitheader,
                          -expires => 'Fri, 01-Jan-2038 00:00:00 GMT');
    }
    else {
        $cgi->remove_cookie('SPLITHEADER');
    }

    $vars->{'message'} = "change_columns";

    my $search;
    if (defined $cgi->param('saved_search')) {
        $search = new Bugzilla::Search::Saved($cgi->param('saved_search'));
    }

    if ($cgi->param('save_columns_for_search')
        && defined $search && $search->user->id == Bugzilla->user->id) 
    {
        my $params = new Bugzilla::CGI($search->url);
        $params->param('columnlist', join(",", @collist));
        $search->set_url($params->query_string());
        $search->update();
    }

    my $params = new Bugzilla::CGI($cgi->param('rememberedquery'));
    $params->param('columnlist', join(",", @collist));
    $vars->{'redirect_url'} = "buglist.cgi?".$params->query_string();


    # If we're running on Microsoft IIS, using cgi->redirect discards
    # the Set-Cookie lines -- workaround is to use the old-fashioned 
    # redirection mechanism. See bug 214466 for details.
    if ($ENV{'SERVER_SOFTWARE'} =~ /Microsoft-IIS/
        || $ENV{'SERVER_SOFTWARE'} =~ /Sun ONE Web/)
    {
      print $cgi->header(-type => "text/html",
                         -refresh => "0; URL=$vars->{'redirect_url'}");
    }
    else {
      print $cgi->redirect($vars->{'redirect_url'});
      exit;
    }
    
    $template->process("global/message.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if (defined $cgi->param('columnlist')) {
    @collist = split(/[ ,]+/, $cgi->param('columnlist'));
} elsif (defined $cgi->cookie('COLUMNLIST')) {
    @collist = split(/ /, $cgi->cookie('COLUMNLIST'));
} else {
    @collist = DEFAULT_COLUMN_LIST;
}

$vars->{'collist'} = \@collist;
$vars->{'splitheader'} = $cgi->cookie('SPLITHEADER') ? 1 : 0;

$vars->{'buffer'} = $cgi->query_string();

my $search;
if (defined $cgi->param('query_based_on')) {
    my $searches = Bugzilla->user->queries;
    my ($search) = grep($_->name eq $cgi->param('query_based_on'), @$searches);

    if ($search) {
        $vars->{'saved_search'} = $search;
    }
}

# Generate and return the UI (HTML page) from the appropriate template.
print $cgi->header();
$template->process("list/change-columns.html.tmpl", $vars)
  || ThrowTemplateError($template->error());
