#!/usr/bin/perl -wT
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Keyword;

my $user = Bugzilla->login();

my $cgi = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars = {};

# Run queries against the shadow DB.
Bugzilla->switch_to_shadow_db;

$vars->{'keywords'} = Bugzilla::Keyword->get_all_with_bug_count();
$vars->{'caneditkeywords'} = $user->in_group("editkeywords");

print $cgi->header();
$template->process("reports/keywords.html.tmpl", $vars)
  || ThrowTemplateError($template->error());
