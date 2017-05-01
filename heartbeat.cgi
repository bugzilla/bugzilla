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

my $ok = eval {
    # Ensure that any Throw*Error calls just use die, rather than trying to return html...
    Bugzilla->error_mode(ERROR_MODE_DIE);
    my $memcached    = Bugzilla->memcached;
    my $dbh          = Bugzilla->dbh;
    my $database_ok  = $dbh->ping;
    my $versions     = $memcached->{memcached}->server_versions;
    my $memcached_ok = keys %$versions;

    die "database not available"            unless $database_ok;
    die "memcached server(s) not available" unless $memcached_ok;
    die "mod_perl not configured?"          unless $ENV{MOD_PERL};
    die "BUGZILLA_UNSAFE_AUTH_DELEGATION"   if $ENV{BUGZILLA_UNSAFE_AUTH_DELEGATION};
    1;
};
warn "heartbeat error: $@" if !$ok && $@;

my $cgi = Bugzilla->cgi;
print $cgi->header(-type => 'text/plain', -status => $ok ? '200 OK' : '500 Internal Server Error');
print $ok ? "Bugzilla OK\n" : "Bugzilla NOT OK\n";

if ($ENV{MOD_PERL}) {
    my $r = $cgi->r;
    # doing this supresses the error document, but does not change the http response code.
    $r->rflush;
    $r->status(200);
}
