# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum;
use Mojo::Base 'Mojolicious';

# Needed for its exit() overload, must happen early in execution.
use CGI::Compile;

use Bugzilla          ();
use Bugzilla::BugMail ();
use Bugzilla::CGI     ();
use Bugzilla::Constants qw(bz_locations);
use Bugzilla::Extension             ();
use Bugzilla::Install::Requirements ();
use Bugzilla::Logging;
use Bugzilla::Quantum::CGI;
use Bugzilla::Quantum::SES;
use Bugzilla::Quantum::Static;
use Mojo::Loader qw( find_modules );
use Module::Runtime qw( require_module );
use Bugzilla::Util ();
use Cwd qw(realpath);
use MojoX::Log::Log4perl::Tiny;

has 'static' => sub { Bugzilla::Quantum::Static->new };

sub startup {
    my ($self) = @_;

    DEBUG('Starting up');
    $self->plugin('Bugzilla::Quantum::Plugin::Glue');
    $self->plugin('Bugzilla::Quantum::Plugin::Hostage');
    $self->plugin('Bugzilla::Quantum::Plugin::BlockIP');
    $self->plugin('Bugzilla::Quantum::Plugin::BasicAuth');

    Bugzilla::Extension->load_all();
    if ( $self->mode ne 'development' ) {
        Bugzilla->preload_features();
        DEBUG('preloading templates');
        Bugzilla->preload_templates();
        DEBUG('done preloading templates');
        require_module($_) for find_modules('Bugzilla::User::Setting');

        $self->hook(
            after_static => sub {
                my ($c) = @_;
                $c->res->headers->cache_control('public, max-age=31536000');
            }
        );
    }

    my $r = $self->routes;
    Bugzilla::Quantum::CGI->load_all($r);
    Bugzilla::Quantum::CGI->load_one( 'bzapi_cgi', 'extensions/BzAPI/bin/rest.cgi' );

    Bugzilla::WebService::Server::REST->preload;

    $r->any('/')->to('CGI#index_cgi');
    $r->any('/bug/<id:num>')->to('CGI#show_bug_cgi');
    $r->any('/<id:num>')->to('CGI#show_bug_cgi');

    $r->any('/rest')->to('CGI#rest_cgi');
    $r->any('/rest.cgi/*PATH_INFO')->to( 'CGI#rest_cgi' => { PATH_INFO => '' } );
    $r->any('/rest/*PATH_INFO')->to( 'CGI#rest_cgi' => { PATH_INFO => '' } );
    $r->any('/extensions/BzAPI/bin/rest.cgi/*PATH_INFO')->to('CGI#bzapi_cgi');
    $r->any('/bzapi/*PATH_INFO')->to('CGI#bzapi_cgi');

    $r->get(
        '/__lbheartbeat__' => sub {
            my $c = shift;
            $c->reply->file( $c->app->home->child('__lbheartbeat__') );
        },
    );

    $r->get(
        '/__version__' => sub {
            my $c = shift;
            $c->reply->file( $c->app->home->child('version.json') );
        },
    );

    $r->get(
        '/version.json' => sub {
            my $c = shift;
            $c->reply->file( $c->app->home->child('version.json') );
        },
    );

    $r->get('/__heartbeat__')->to('CGI#heartbeat_cgi');
    $r->get('/robots.txt')->to('CGI#robots_cgi');

    $r->any('/review')->to( 'CGI#page_cgi' => { 'id' => 'splinter.html' } );
    $r->any('/user_profile')->to( 'CGI#page_cgi' => { 'id' => 'user_profile.html' } );
    $r->any('/userprofile')->to( 'CGI#page_cgi' => { 'id' => 'user_profile.html' } );
    $r->any('/request_defer')->to( 'CGI#page_cgi' => { 'id' => 'request_defer.html' } );
    $r->any('/login')->to( 'CGI#index_cgi' => { 'GoAheadAndLogIn' => '1' } );

    $r->any( '/:new_bug' => [ new_bug => qr{new[-_]bug} ] )->to('CGI#new_bug_cgi');

    my $ses_auth = $r->under(
        '/ses' => sub {
            my ($c) = @_;
            my $lc = Bugzilla->localconfig;

            return $c->basic_auth( 'SES', $lc->{ses_username}, $lc->{ses_password} );
        }
    );
    $ses_auth->any('/index.cgi')->to('SES#main');

    Bugzilla::Hook::process( 'app_startup', { app => $self } );
}

1;
