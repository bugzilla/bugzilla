#!/usr/bin/perl

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

BEGIN {
  use Bugzilla;
  Bugzilla->extensions;
}

use Bugzilla::Extension::PhabBugz::Daemon;
Bugzilla::Extension::PhabBugz::Daemon->start();

=head1 NAME

phabbugz_feed.pl - Query Phabricator for interesting changes and update bugs related to revisions.

=head1 SYNOPSIS

  phabbugz_feed.pl [OPTIONS] COMMAND

    OPTIONS:
      -f        Run in the foreground (don't detach)
      -d        Output a lot of debugging information
      -p file   Specify the file where phabbugz_feed.pl should store its current
                process id. Defaults to F<data/phabbugz_feed.pl.pid>.
      -n name   What should this process call itself in the system log?
                Defaults to the full path you used to invoke the script.

    COMMANDS:
      start     Starts a new phabbugz_feed daemon if there isn't one running already
      stop      Stops a running phabbugz_feed daemon
      restart   Stops a running phabbugz_feed if one is running, and then
                starts a new one.
      check     Report the current status of the daemon.
      install   On some *nix systems, this automatically installs and
                configures phabbugz_feed.pl as a system service so that it will
                start every time the machine boots.
      uninstall Removes the system service for phabbugz_feed.pl.
      help      Display this usage info
