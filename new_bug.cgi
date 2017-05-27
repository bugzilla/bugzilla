#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
#
# Contributor(s): Sebastin Santy <sebastinssanty@gmail.com>
#
##############################################################################
#
# new_bug.cgi
# -------------
# Single page interface to file bugs
#
##############################################################################

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Error;
use Bugzilla::Bug;
use Bugzilla::User;
use Bugzilla::Hook;
use Bugzilla::Product;
use Bugzilla::Classification;
use Bugzilla::Keyword;
use Bugzilla::Token;
use Bugzilla::Field;
use Bugzilla::Status;
use Bugzilla::UserAgent;

my $user = Bugzilla->login(LOGIN_REQUIRED);

my $cgi = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars = {};

print $cgi->header();
$template->process("bug/new_bug.html.tmpl",
                    $vars)
  or ThrowTemplateError($template->error());          

