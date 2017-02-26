#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.14.0;
use strict;
use warnings;

use File::Basename;
use File::Spec;

BEGIN {
    require lib;
    my $dir = File::Spec->rel2abs( dirname(__FILE__) );
    lib->import(
        $dir,
        File::Spec->catdir( $dir, "lib" ),
        File::Spec->catdir( $dir, qw(local lib perl5) )
    );

    # disable "use lib" from now on
    no warnings qw(redefine);
    *lib::import = sub { };
}

BEGIN { $ENV{BZ_PLACK} = 'Plack' }

use Bugzilla::Constants ();

use Plack;
use Plack::Builder;
use Plack::App::URLMap;
use Plack::App::WrapCGI;
use Plack::Response;

use constant STATIC => qw(
    data/assets/
    data/webdot/
    docs/
    extensions/[^/]+/web/
    graphs/
    images/
    js/
    skins/
    robots\.txt
);

my $app = builder {
    my $static_paths
        = join( '|', sort { length $b <=> length $a || $a cmp $b } STATIC );
    enable 'Static',
        path => qr{^/(?:$static_paths)},
        root => Bugzilla::Constants::bz_locations->{cgi_path};

    my $shutdown_app
        = Plack::App::WrapCGI->new( script => 'shutdown.cgi' )->to_app;
    my @scripts = glob('*.cgi');

    my %cgi_app;
    foreach my $script (@scripts) {
        my $base_name = basename($script);

        next if $base_name eq 'shutdown.cgi';
        my $app
            = eval { Plack::App::WrapCGI->new( script => $script )->to_app };

        # Some CGI scripts won't compile if not all optional Perl modules are
        # installed. That's expected.
        unless ($app) {
            warn "Cannot compile $script: $@\nSkipping!\n";
            next;
        }

        my $wrapper = sub {
            my $ret = Bugzilla::init_page();
            my $res
                = ( $ret eq '-1' && $script ne 'editparams.cgi' )
                ? $shutdown_app->(@_)
                : $app->(@_);
            Bugzilla::_cleanup();
            return $res;
        };
        $cgi_app{$base_name} = $wrapper;
    }

    foreach my $cgi_name ( keys %cgi_app ) {
        mount "/$cgi_name" => $cgi_app{$cgi_name};
    }

    # so mount / => $app will make *all* files redirect to the index.
    # instead we use an inline middleware to rewrite / to /index.cgi
    enable sub {
        my $app = shift;
        return sub {
            my $env = shift;
            warn "$env->{PATH_INFO} / $env->{SCRIPT_NAME}\n";
            $env->{PATH_INFO} = '/index.cgi' if $env->{PATH_INFO} eq '/';
            return $app->($env);
        };
    };

    mount "/rest" => $cgi_app{"rest.cgi"};

};

unless (caller) {
    require Plack::Runner;
    my $runner = Plack::Runner->new;
    $runner->parse_options(@ARGV);
    $runner->run($app);
    exit 0;
}

return $app;
