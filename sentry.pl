#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

#
# report errors to sentry
# expects a filename with a Data::Dumper serialised parameters
# called by Bugzilla::Sentry
#

use strict;
use warnings;

BEGIN {
    delete $ENV{SERVER_SOFTWARE};
}

use FindBin qw($Bin);
use lib $Bin;
use lib "$Bin/lib";

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::RNG qw(irand);
use Fcntl qw(:flock);
use File::Slurp;
use HTTP::Request::Common;
use JSON ();
use LWP::UserAgent;
use POSIX qw(setsid nice);
use Safe;
use URI;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
nice(19);

# detach
open(STDIN, '</dev/null');
open(STDOUT, '>/dev/null');
open(STDERR, '>/dev/null');
setsid();

# grab sentry server url
my $sentry_uri = Bugzilla->params->{sentry_uri} || '';
exit(1) unless $sentry_uri;

# read data dump
exit(1) unless my $filename = shift;
my $dump = read_file($filename);
unlink($filename);

# deserialise
my $cpt = new Safe;
$cpt->reval($dump) || exit(1);
my $data = ${$cpt->varglob('VAR1')};

# split the sentry uri
my $uri = URI->new($sentry_uri);
my ($public_key, $secret_key) = split(/:/, $uri->userinfo);
$uri->userinfo(undef);
my $project_id = $uri->path;
$project_id =~ s/^\///;
$uri->path("/api/$project_id/store/");

# build the message
my $message = JSON->new->utf8(1)->pretty(0)->allow_nonref(1)->encode($data);
my %header = (
    'X-Sentry-Auth' => sprintf(
        "Sentry sentry_version=%s, sentry_timestamp=%s, sentry_key=%s, sentry_client=%s, sentry_secret=%s",
        '2.0',
        (time),
        $public_key,
        'bugzilla/4.2',
        $secret_key,
    ),
    'Content-Type' => 'application/json'
);

# ensure we send warnings one at a time per webhead
flock(DATA, LOCK_EX);

# and post to sentry
my $request = POST $uri->canonical, %header, Content => $message;
my $response = LWP::UserAgent->new(timeout => 10)->request($request);

__DATA__
this exists so the flock() code works.
do not remove this data section.
