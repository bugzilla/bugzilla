#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This file has detailed POD docs, do "perldoc checksetup.pl" to see them.

######################################################################
# Initialization
######################################################################

use 5.10.1;
use strict;
use warnings;

use File::Basename;
use File::Spec;

BEGIN {
  require lib;
  my $dir = File::Spec->rel2abs(dirname(__FILE__));
  my $base = File::Spec->catdir($dir, "..");
  lib->import(
    $base,
    File::Spec->catdir($base, "lib"),
    File::Spec->catdir($base, qw(local lib perl5))
  );
  chdir $base;
}

use Bugzilla;
BEGIN { Bugzilla->extensions }
use Bugzilla::Mailer;

my $msg = do {
  local $/ = undef;
  binmode STDIN, ':bytes';
  <STDIN>;
};

MessageToMTA($msg);
