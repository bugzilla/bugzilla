# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

use constant DISPLAY => 99;
#use constant DISPLAY => 0;

use Test::More tests => 12;
#use Test::More tests => 4;

my $pid;

# Start the Xvfb server first
$pid = xserver_start();
ok($pid, "X Server started with PID $pid on display " . DISPLAY);
ok(open(XPID, ">testing.x.pid"), "Opening testing.x.pid");
ok((print XPID $pid), "Writing testing.x.pid");
ok(close(XPID),  "Closing testing.x.pid");

# Start the VNC service second
ok($pid = vnc_start(), "VNC desktop started with PID $pid");
ok(open(VNCPID, ">testing.vnc.pid"), "Opening testing.vnc.pid");
ok((print VNCPID $pid), "Writing testing.vnc.pid");
ok(close(VNCPID),  "Closing testing.vnc.pid");

# Start the selenium server third
ok($pid = selenium_start(), "Selenium RC server started with PID $pid");
ok(open(SPID, ">testing.selenium.pid"), "Opening testing.selenium.pid");
ok((print SPID $pid), "Writing testing.selenium.pid");
ok(close(SPID),  "Closing testing.selenium.pid");

sleep(10);

# Subroutines

sub xserver_start {
    my $pid;
    my @x_cmd = qw(Xvfb -ac -screen 0 1600x1200x24 -fbdir /tmp);
    push(@x_cmd, ":" . DISPLAY);
    $pid = fork();
    if (!$pid) {
        open(STDOUT, ">/dev/null");
        open(STDERR, ">/dev/null");
        exec(@x_cmd) || die "unable to execute: $!";
    }
    else {
        return $pid;
    }
    return 0;
}

sub vnc_start {
    my @vnc_cmd = qw(x11vnc -viewonly -forever -nopw -quiet -display);
    push(@vnc_cmd, ":" . DISPLAY);
    my $pid = fork();
    if (!$pid) {
        open(STDOUT, ">/dev/null");
        open(STDERR, ">/dev/null");
        exec(@vnc_cmd) || die "unabled to execute: $!";
    }
    return $pid;
}

sub selenium_start {
    my @selenium_cmd = qw(java -jar ../config/selenium-server-standalone.jar
                               -firefoxProfileTemplate ../config/firefox
                               -log ../config/selenium.log
                               -singlewindow);
    unshift(@selenium_cmd, "env", "DISPLAY=:" . DISPLAY);
    my $pid = fork();
    if (!$pid) {
        open(STDOUT, ">/dev/null");
        open(STDERR, ">/dev/null");
        exec(@selenium_cmd) || die "unable to execute: $!";
    }
    return $pid;
}
