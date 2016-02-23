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

use File::Basename;
use File::Spec;
BEGIN {
    require lib;
    my $dir = dirname(__FILE__);
    lib->import($dir, File::Spec->catdir($dir, "lib"), File::Spec->catdir($dir, qw(local lib perl5)));
}

use Bugzilla::Constants ();

use Plack;
use Plack::Builder;
use Plack::App::URLMap;
use Plack::App::WrapCGI;
use Plack::Response;

use constant STATIC => qw(
    data/assets
    data/webdot
    docs
    extensions/[^/]+/web
    graphs
    images
    js
    skins
);

builder {
    my $static_paths = join('|', STATIC);
    enable 'Static',
        path => qr{^/($static_paths)/},
        root => Bugzilla::Constants::bz_locations->{cgi_path};

    $ENV{BZ_PLACK} = 'Plack/' . Plack->VERSION;

    my $map = Plack::App::URLMap->new;

    my @cgis = glob('*.cgi');
    my $shutdown_app = Plack::App::WrapCGI->new(script => 'shutdown.cgi')->to_app;

    foreach my $cgi_script (@cgis) {
        my $app = eval { Plack::App::WrapCGI->new(script => $cgi_script)->to_app };
        # Some CGI scripts won't compile if not all optional Perl modules are
        # installed. That's expected.
        if ($@) {
            warn "Cannot compile $cgi_script. Skipping!\n";
            next;
        }

        my $wrapper = sub {
            my $ret = Bugzilla::init_page();
            my $res = ($ret eq '-1' && $cgi_script ne 'editparams.cgi') ? $shutdown_app->(@_) : $app->(@_);
            Bugzilla::_cleanup();
            return $res;
        };

        my $base_name = basename($cgi_script);
        $map->map('/' => $wrapper) if $cgi_script eq 'index.cgi';
        $map->map('/rest' => $wrapper) if $cgi_script eq 'rest.cgi';
        $map->map("/$base_name" => $wrapper);
    }
    my $app = $map->to_app;
};
