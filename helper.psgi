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
use Plack::Request;
use Plack::Response;

my $app = sub {
    my $env     = shift;
    my $req     = Plack::Request->new($env);
    my $res     = Plack::Response->new(404);
    my $urlbase = Bugzilla->localconfig->{urlbase};
    my $path    = $req->path;

    if ( $path eq '/quicksearch.html' ) {
        $res->redirect( $urlbase . 'page.cgi?id=quicksearch.html', 301 );
    }
    elsif ( $path eq '/bugwritinghelp.html') {
        $res->redirect( $urlbase . 'page.cgi?id=bug-writing.html', 301 );
    }
    elsif ( $path =~ m{^/(\d+)$}s ) {
        $res->redirect( $urlbase . "show_bug.cgi?id=$1", 301 );
    }
    else {
        $res->body('not found');
    }
    return $res->finalize;
};