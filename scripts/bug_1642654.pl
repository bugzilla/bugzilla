#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This script disables users who have not logged into BMO within the last four
# years.

use 5.10.1;
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir rel2abs);

BEGIN {
  require lib;
  my $dir = rel2abs(catdir(dirname(__FILE__), '..'));
  lib->import($dir, catdir($dir, 'lib'), catdir($dir, qw(local lib perl5)));
}

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::User;
use Bugzilla::Util;

use constant NEW_DISABLE_MESSAGE => <<'EOF';
Your account has been disabled because you have not logged on to
bugzilla.mozilla.org in a long time. You can reactivate your account
by submitting a request to reset your password from the
<a href="/login">login page</a>.
EOF

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my $sql = <<'EOF';
SELECT
  profiles.userid
FROM
  profiles
WHERE
  profiles.disabledtext like '%Your account has been disabled because you have not logged on to%bugzilla.mozilla.org recently%'
ORDER BY
  profiles.userid
EOF

say STDERR 'looking for users previous disabled as inactive';
my $userids = Bugzilla->dbh->selectcol_arrayref($sql);
my $total = scalar @{$userids};
die "no matching users found.\n" unless $total;

say STDERR "found $total previously disabled inactive user" . ($total == 1 ? '' : 's');
say STDERR 'press <ctrl-c> to abort, or <enter> to start';
getc;

my $count = 0;
foreach my $userid (@{$userids}) {
  indicate_progress({total => $total, current => ++$count});
  my $user = Bugzilla::User->new($userid);
  $user->set_disabledtext(NEW_DISABLE_MESSAGE);
  $user->set_password_change_required(1);
  $user->set_password_change_reason('Inactive Account');
  $user->update();
}
