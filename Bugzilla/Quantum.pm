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
use utf8;
use Encode;

use Bugzilla          ();
use Bugzilla::BugMail ();
use Bugzilla::CGI     ();
use Bugzilla::Constants qw(bz_locations);
use Bugzilla::Extension             ();
use Bugzilla::Install::Requirements ();
use Bugzilla::Logging;
use Bugzilla::Quantum::CGI;
use Bugzilla::Quantum::OAuth2 qw(oauth2);
use Bugzilla::Quantum::SES;
use Bugzilla::Quantum::Home;
use Bugzilla::Quantum::API;
use Bugzilla::Quantum::Static;
use Mojo::Loader qw( find_modules );
use Module::Runtime qw( require_module );
use Bugzilla::Util ();
use Cwd qw(realpath);
use MojoX::Log::Log4perl::Tiny;
use Bugzilla::WebService::Server::REST;

has 'static' => sub { Bugzilla::Quantum::Static->new };

sub startup {
  my ($self) = @_;

  DEBUG('Starting up');
  $self->plugin('Bugzilla::Quantum::Plugin::BlockIP');
  $self->plugin('Bugzilla::Quantum::Plugin::Glue');
  $self->plugin('Bugzilla::Quantum::Plugin::Hostage')
    unless $ENV{BUGZILLA_DISABLE_HOSTAGE};
  $self->plugin('Bugzilla::Quantum::Plugin::SizeLimit')
    unless $ENV{BUGZILLA_DISABLE_SIZELIMIT};
  $self->plugin('ForwardedFor') if Bugzilla->has_feature('better_xff');
  $self->plugin('Bugzilla::Quantum::Plugin::Helpers');

  # OAuth2 Support
  oauth2($self);

  # hypnotoad is weird and doesn't look for MOJO_LISTEN itself.
  $self->config(
    hypnotoad => {
      proxy              => $ENV{MOJO_REVERSE_PROXY} // 1,
      heartbeat_interval => $ENV{MOJO_HEARTBEAT_INTERVAL} // 10,
      heartbeat_timeout  => $ENV{MOJO_HEARTBEAT_TIMEOUT} // 120,
      inactivity_timeout => $ENV{MOJO_INACTIVITY_TIMEOUT} // 120,
      workers            => $ENV{MOJO_WORKERS} // 1,
      clients            => $ENV{MOJO_CLIENTS} // 200,
      spare              => $ENV{MOJO_SPARE} // 1,
      listen             => [$ENV{MOJO_LISTEN} // 'http://*:3000'],
    },
  );

  # Make sure each httpd child receives a different random seed (bug 476622).
  # Bugzilla::RNG has one srand that needs to be called for
  # every process, and Perl has another. (Various Perl modules still use
  # the built-in rand(), even though we never use it in Bugzilla itself,
  # so we need to srand() both of them.)
  # Also, ping the dbh to force a reconnection.
  Mojo::IOLoop->next_tick(sub {
    Bugzilla::RNG::srand();
    srand();
    eval { Bugzilla->dbh->ping };
  });

  Bugzilla::Extension->load_all();
  if ($self->mode ne 'development') {
    Bugzilla->preload_features();
    DEBUG('preloading templates');
    Bugzilla->preload_templates();
    DEBUG('done preloading templates');
    require_module($_) for find_modules('Bugzilla::User::Setting');

    $self->hook(
      after_static => sub {
        my ($c) = @_;
        $c->res->headers->cache_control('public, max-age=31536000, immutable');
      }
    );
  }
  Bugzilla::WebService::Server::REST->preload;

  $self->setup_routes;

  Bugzilla::Hook::process('app_startup', {app => $self});
}

sub setup_routes {
  my ($self) = @_;

  my $r = $self->routes;
  Bugzilla::Quantum::CGI->load_all($r);
  Bugzilla::Quantum::CGI->load_one('bzapi_cgi',
    'extensions/BzAPI/bin/rest.cgi');

  $r->get('/home')->to('Home#index');
  $r->any('/')->to('CGI#index_cgi');
  $r->any('/bug/<id:num>')->to('CGI#show_bug_cgi');
  $r->any('/<id:num>')->to('CGI#show_bug_cgi');
  $r->get(
    '/testagent.cgi' => sub {
      my $c = shift;
      $c->render(text => "OK Mojolicious");
    }
  );

  $r->any('/rest')->to('CGI#rest_cgi');
  $r->any('/rest.cgi/*PATH_INFO')->to('CGI#rest_cgi' => {PATH_INFO => ''});
  $r->any('/rest/*PATH_INFO')->to('CGI#rest_cgi' => {PATH_INFO => ''});
  $r->any('/extensions/BzAPI/bin/rest.cgi/*PATH_INFO')->to('CGI#bzapi_cgi');
  $r->any('/latest/*PATH_INFO')->to('CGI#bzapi_cgi');
  $r->any('/bzapi/*PATH_INFO')->to('CGI#bzapi_cgi');

  $r->static_file('/__lbheartbeat__');
  $r->static_file('/__version__' =>
      {file => 'version.json', content_type => 'application/json'});
  $r->static_file('/version.json', {content_type => 'application/json'});

  $r->page('/review',        'splinter.html');
  $r->page('/user_profile',  'user_profile.html');
  $r->page('/userprofile',   'user_profile.html');
  $r->page('/request_defer', 'request_defer.html');

  $r->get('/__heartbeat__')->to('CGI#heartbeat_cgi');
  $r->get('/robots.txt')->to('CGI#robots_cgi');
  $r->any('/login')->to('CGI#index_cgi' => {'GoAheadAndLogIn' => '1'});
  $r->any('/:new_bug' => [new_bug => qr{new[-_]bug}])->to('CGI#new_bug_cgi');

  $r->get('/api/user/profile')->to('API#user_profile');

  my $ses_auth = $r->under(
    '/ses' => sub {
      my ($c) = @_;
      my $lc = Bugzilla->localconfig;

      return $c->basic_auth('SES', $lc->{ses_username}, $lc->{ses_password});
    }
  );
  $ses_auth->any('/index.cgi')->to('SES#main');
}

1;
