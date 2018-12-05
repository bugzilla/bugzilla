# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Enforce high standards against code that will be installed

use 5.14.0;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5 t);

use Test::More;
use File::Spec::Functions ':ALL';

BEGIN {
  # Don't run tests for installs or automated tests
  unless ($ENV{RELEASE_TESTING}) {
    plan(skip_all => "Author tests not required for installation");
  }
  my $config = catfile('t', 'critic-core.ini');
  unless (eval "use Test::Perl::Critic -profile => '$config'; 1") {
    plan skip_all => 'Test::Perl::Critic required to criticise code';
  }
}

# need to skip t/
all_critic_ok('Bugzilla.pm', 'Bugzilla/', glob("*.cgi"), glob("*.pl"),);
