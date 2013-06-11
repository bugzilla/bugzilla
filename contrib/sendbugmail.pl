#!/usr/bin/perl -wT
#
#                    sendbugmail.pl
#
# Nick Barnes, Ravenbrook Limited, 2004-04-01.
#
# Bugzilla email script for Bugzilla 2.17.4 and later.  Invoke this to send
# bugmail for a bug which has been changed directly in the database.
# This uses Bugzilla's own BugMail facility, and will email the
# users associated with the bug.  Replaces the old "processmail"
# script.
# 
# Usage: perl -T contrib/sendbugmail.pl bug_id user_email

use 5.10.1;
use strict;
use lib qw(. lib);

use Bugzilla;
use Bugzilla::Util;
use Bugzilla::BugMail;
use Bugzilla::User;

my $dbh = Bugzilla->dbh;

sub usage {
    say STDERR "Usage: $0 bug_id user_email";
    exit;
}

if (($#ARGV < 1) || ($#ARGV > 2)) {
    usage();
}

# Get the arguments.
my $bugnum = $ARGV[0];
my $changer = $ARGV[1];

# Validate the bug number.
if (!($bugnum =~ /^(\d+)$/)) {
  say STDERR "Bug number \"$bugnum\" not numeric.";
  usage();
}

detaint_natural($bugnum);

my ($id) = $dbh->selectrow_array("SELECT bug_id FROM bugs WHERE bug_id = ?", 
                                 undef, $bugnum);

if (!$id) {
  say STDERR "Bug number $bugnum does not exist.";
  usage();
}

# Validate the changer address.
my $match = Bugzilla->params->{'emailregexp'};
if ($changer !~ /$match/) {
    say STDERR "Changer \"$changer\" doesn't match email regular expression.";
    usage();
}
my $changer_user = new Bugzilla::User({ name => $changer });
unless ($changer_user) {
    say STDERR "\"$changer\" is not a valid user.";
    usage();
}

# Send the email.
my $outputref = Bugzilla::BugMail::Send($bugnum, {'changer' => $changer_user });

# Report the results.
my $sent = scalar(@{$outputref->{sent}});

if ($sent) {
    say "email sent to $sent recipients:";
} else {
    say "No email sent.";
}

foreach my $sent (@{$outputref->{sent}}) {
  say "  $sent";
}

# This document is copyright (C) 2004 Perforce Software, Inc.  All rights
# reserved.
# 
# Redistribution and use of this document in any form, with or without
# modification, is permitted provided that redistributions of this
# document retain the above copyright notice, this condition and the
# following disclaimer.
# 
# THIS DOCUMENT IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDERS AND CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# DOCUMENT, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
