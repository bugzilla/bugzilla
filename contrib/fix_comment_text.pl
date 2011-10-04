#!/usr/bin/perl 
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
# 
# Software distributed under the License is distributed on an "AS
# IS" basis,  WITHOUT WARRANTY OF ANY KIND,  either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
# 
# The Initial Developer of the Original Code is Mozilla Foundation 
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
#===============================================================================
#
#         FILE:  fix_comment_text.pl
#
#        USAGE:  ./fix_comment_text.pl <comment_id>
#
#  DESCRIPTION:  Updates a comment in Bugzilla with the text after __DATA__
#
#      OPTIONS:  <comment_id> - The comment id from longdescs with the comment 
#                to be replaced.
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  David Lawrence (:dkl), dkl@mozilla.com
#      COMPANY:  Mozilla Foundation
#      VERSION:  1.0
#      CREATED:  06/20/2011 03:40:22 PM
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use lib ".";

use Bugzilla;
use Bugzilla::Util qw(detaint_natural);

my $comment_id = shift;

if (!detaint_natural($comment_id)) {
    print "Error: invalid comment id or comment id not provided.\n" .
          "Usage: ./fix_comment_text.pl <comment_id>\n";
    exit(1);
}

my $dbh = Bugzilla->dbh;

my $comment = join("",  <DATA>);

if ($comment =~ /ENTER NEW COMMENT TEXT HERE/) {
    print "Please enter the new comment text in the script " .
          "after the __DATA__ marker.\n";
    exit(1);
}

$dbh->bz_start_transaction;

Bugzilla->dbh->do(
    "UPDATE longdescs SET thetext = ? WHERE comment_id = ?", 
    undef, $comment, $comment_id);

$dbh->bz_commit_transaction;

exit(0);

__DATA__
ENTER NEW COMMENT TEXT HERE BELOW THE __DATA__ MARKER!
