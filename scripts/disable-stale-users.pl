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
use File::Spec::Functions qw(catfile catdir rel2abs);
use Cwd qw(realpath);

BEGIN {
  require lib;
  my $dir = rel2abs(catdir(dirname(__FILE__), '..'));
  lib->import($dir, catdir($dir, 'lib'), catdir($dir, qw(local lib perl5)));
}

use Bugzilla::Constants;
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::User;
use Bugzilla::Util;
use Bugzilla;
use Date::Format;
use Date::Parse;
use DateTime;
use Getopt::Long qw(:config gnu_getopt);
use Try::Tiny;

use constant DISABLE_MESSAGE => <<'EOF';
Your account has been disabled because you have not logged on to
bugzilla.mozilla.org recently. Please contact bmo-mods@mozilla.com if you
wish to reactivate your account.
EOF

use constant IDLE_PERIOD_MONTHS => 4 * 12;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);

my ($list, $dump_sql);
GetOptions('list' => \$list, 'sql' => \$dump_sql) or die <<'EOF';
usage: disable-stale-users.pl [--list][--sql]
  --list    : list email addresses of impacted users, do not disable any accounts
  --sql     : dump sql used to determine impacted users, do not disable any accounts
EOF

Bugzilla->extensions;
Bugzilla->set_user(Bugzilla::User->check({name => 'automation@bmo.tld'}));
my $dbh  = Bugzilla->dbh;
my $date = DateTime->now()->subtract(months => IDLE_PERIOD_MONTHS)->ymd();

my $sql = <<'EOF';
SELECT
  profiles.userid AS userid,
  profiles.login_name AS login_name
FROM
  profiles
  LEFT JOIN
    components
    ON components.watch_user = profiles.userid
WHERE
  profiles.login_name != 'nobody@mozilla.org'
  AND components.id IS NULL
  AND NOT profiles.login_name LIKE '%.bugs'
  AND NOT profiles.login_name LIKE '%.tld'
  AND profiles.is_enabled = 1
  AND profiles.creation_ts < ?
  AND (profiles.last_seen_date IS NULL OR profiles.last_seen_date <= ?)
ORDER BY
  profiles.userid
EOF

if ($dump_sql) {
  $sql =~ s/[?]/$date/g;
  print $sql;
  exit;
}

say STDERR "looking for users inactive since $date";
my $users = $dbh->selectall_arrayref($sql, {Slice => {}}, $date, $date);
my $total = scalar @$users;
die "no matching users found.\n" unless $total;

if ($list) {
  foreach my $user_row (@$users) {
    say $user_row->{login_name};
  }
  exit;
}

say STDERR "found $total stale user" . ($total == 1 ? '' : 's');
say STDERR 'press <ctrl-c> to disable users, or <enter> to start';
getc();

my $count = 0;
foreach my $user_row (@$users) {
  indicate_progress({total => $total, current => ++$count});
  my $user = Bugzilla::User->new($user_row->{userid});
  $user->set_disabledtext(DISABLE_MESSAGE);
  $user->update();
}
