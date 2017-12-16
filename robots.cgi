#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Update;
use Digest::MD5 qw(md5_hex);
use List::MoreUtils qw(any);

# Check whether or not the user is logged in
my $user     = Bugzilla->login(LOGIN_OPTIONAL);
my $cgi      = Bugzilla->cgi;
my $template = Bugzilla->template;

my %vars;
print $cgi->header('text/plain');
Bugzilla::Hook::process( "before_robots_txt", { vars => \%vars } );
$template->process( "robots.txt.tmpl", \%vars )
    or ThrowTemplateError( $template->error() );
