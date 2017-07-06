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

if (lc($cgi->request_method) eq 'post') {
     my $token = $cgi->param('token');
     check_hash_token($token, ['new_bug']);
     my $new_bug = Bugzilla::Bug->create({
                short_desc   => scalar($cgi->param('short_desc')),
                product      => scalar($cgi->param('product')),
                component    => scalar($cgi->param('component')),
                bug_severity => 'normal',
                groups       => [],
                op_sys       => 'Unspecified',
                rep_platform => 'Unspecified',
                version      => join(' ', split('_', scalar($cgi->param('version')))),
                cc           => [],
                comment      => scalar($cgi->param('comment')),
            });
     delete_token($token);
     print $cgi->redirect(correct_urlbase() . 'show_bug.cgi?id='.$new_bug->bug_id);
} else {
 print $cgi->header();
$template->process("bug/new_bug.html.tmpl",
                    $vars)
  or ThrowTemplateError($template->error());
}

