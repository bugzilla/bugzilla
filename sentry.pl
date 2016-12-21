#!/usr/bin/perl

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

use 5.10.1;
use strict;
use warnings;
use lib qw(. lib local/lib/perl5);

BEGIN {
    delete $ENV{SERVER_SOFTWARE};

    use Bugzilla::Constants;
    exit(0) unless glob(bz_locations()->{error_reports} . '/*.dump');
}

use Bugzilla;
use Fcntl qw(:flock);
use File::Slurp qw(read_file);
use HTTP::Request::Common;
use LWP::UserAgent;
use POSIX qw(nice);
use URI;

Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
nice(19);

exit(1) unless Bugzilla->params->{sentry_uri};
my $uri = URI->new(Bugzilla->params->{sentry_uri});
my $header = build_header($uri);
exit(1) unless $header;

my $ua = LWP::UserAgent->new(timeout => 10);
if (my $proxy_url = Bugzilla->params->{proxy_url}) {
    $ua->proxy(['http', 'https'], $proxy_url);
}

flock(DATA, LOCK_EX);
foreach my $file (glob(bz_locations()->{error_reports} . '/*.dump')) {
    eval {
        send_file($uri, $header, $file);
    };
}

sub build_header {
    my ($uri) = @_;

    # split the sentry uri
    return undef unless $uri->userinfo && $uri->path;
    my ($public_key, $secret_key) = split(/:/, $uri->userinfo);
    $uri->userinfo(undef);
    my $project_id = $uri->path;
    $project_id =~ s/^\///;
    $uri->path("/api/$project_id/store/");

    # build the header
    return {
        'X-Sentry-Auth' => sprintf(
            "Sentry sentry_version=%s, sentry_timestamp=%s, sentry_key=%s, sentry_client=%s, sentry_secret=%s",
            '2.0',
            (time),
            $public_key,
            'bmo/' . BUGZILLA_VERSION,
            $secret_key,
        ),
        'Content-Type' => 'application/json'
    };
}

sub send_file {
    my ($uri, $header, $filename) = @_;
    # read data dump
    my $message = read_file($filename);
    unlink($filename);

    # and post to sentry
    my $request = POST $uri->canonical, %$header, Content => $message;
    my $response = $ua->request($request);
}

__DATA__
this exists so the flock() code works.
do not remove this data section.
