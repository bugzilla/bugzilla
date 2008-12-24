#!/usr/bin/perl -w
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Mozilla Corporation.
# Portions created by the Initial Developer are Copyright (C) 2008
# Mozilla Corporation. All Rights Reserved.
#
# Contributor(s): 
#   Mark Smith <mark@mozilla.com>
#   Max Kanat-Alexander <mkanat@bugzilla.org>

use strict;
use File::Basename;
BEGIN { chdir dirname($0); }

use lib qw(. lib);
use Bugzilla;
use Bugzilla::JobQueue::Runner;

Bugzilla::JobQueue::Runner->new();

=head1 NAME

jobqueue.pl - Runs jobs in the background for Bugzilla.

=head1 SYNOPSIS

 ./jobqueue.pl [ -f ] [ -d ] { start | stop | restart | check | help | version } 

   -f        Run in the foreground (don't detach)
   -d        Output a lot of debugging information
   start     Starts a new jobqueue daemon if there isn't one running already
   stop      Stops a running jobqueue daemon
   restart   Stops a running jobqueue if one is running, and then
             starts a new one.
   check     Report the current status of the daemon.
   help      Display this usage info
   version   Display the version of jobqueue.pl

=head1 DESCRIPTION

See L<Bugzilla::JobQueue> and L<Bugzilla::JobQueue::Runner>.
