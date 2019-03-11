# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App;
use Mojo::Base 'Mojolicious';

# Needed for its exit() overload, must happen early in execution.
use CGI::Compile;
use utf8;
use Encode;
use FileHandle;    # this is for compat back to 5.10

use Bugzilla          ();
use Bugzilla::BugMail ();
use Bugzilla::CGI     ();
use Bugzilla::Constants qw(bz_locations MAX_STS_AGE);
use Bugzilla::Extension             ();
use Bugzilla::Install::Requirements ();
use Bugzilla::Logging;
use Bugzilla::App::CGI;
use Bugzilla::App::OAuth2::Clients;
use Bugzilla::App::SES;
use Bugzilla::App::Main;
use Bugzilla::App::API;
use Bugzilla::App::Static;
use Mojo::Loader qw( find_modules );
use Module::Runtime qw( require_module );
use Bugzilla::Util ();
use Cwd qw(realpath);
use MojoX::Log::Log4perl::Tiny;
use Bugzilla::WebService::Server::REST;
use Try::Tiny;

has 'static' => sub { Bugzilla::App::Static->new };

sub startup {
  my ($self) = @_;

  TRACE('Starting up');
  $self->plugin('Bugzilla::App::Plugin::BlockIP');
  $self->plugin('Bugzilla::App::Plugin::Glue');
  $self->plugin('Bugzilla::App::Plugin::Hostage')
    unless $ENV{BUGZILLA_DISABLE_HOSTAGE};
  $self->plugin('Bugzilla::App::Plugin::SizeLimit')
    unless $ENV{BUGZILLA_DISABLE_SIZELIMIT};
  $self->plugin('ForwardedFor') if Bugzilla->has_feature('better_xff');
  $self->plugin('Bugzilla::App::Plugin::Helpers');
  $self->plugin('Bugzilla::App::Plugin::OAuth2');

  push @{$self->commands->namespaces}, 'Bugzilla::App::Command';
  push @{$self->renderer->paths}, @{ Bugzilla::Template::_include_path() };

  $self->sessions->cookie_name('bugzilla');
  $self->sessions->default_expiration(60 * 60 * 24 * 7); # 1 week

  $self->hook(
    before_routes => sub {
      my ($c) = @_;
      return if $c->stash->{'mojo.static'};

      # It is possible the regexp is bad.
      # If that is the case, we just log the error and continue on.
      try {
        my $regexp = Bugzilla->params->{block_user_agent};
        if ($regexp && $c->req->headers->user_agent =~ /$regexp/) {
          my $msg = "Contact " . Bugzilla->params->{maintainer};
          $c->respond_to(
            json => {json => {error => $msg}, status => 400},
            any  => {text => "$msg\n",        status => 400},
          );
        }
      }
      catch {
        ERROR($_);
      };
    }
  );

  $ENV{MOJO_MAX_LINE_SIZE} ||= 1024 * 10; # Mojo default is 8kb

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
        my $version = $c->stash->{static_file_version};
        if ($version && $version > Bugzilla->VERSION) {
          $c->res->headers->cache_control('no-cache, no-store');
        }
        else {
          $c->res->headers->cache_control('public, max-age=31536000, immutable');
        }
      }
    );
  }
  $self->hook(after_dispatch => sub {
    my ($c) = @_;
    if ($c->req->is_secure
      && ! $c->res->headers->strict_transport_security
      && Bugzilla->params->{'strict_transport_security'} ne 'off')
    {
      my $sts_opts = 'max-age=' . MAX_STS_AGE;
      if (Bugzilla->params->{'strict_transport_security'} eq 'include_subdomains') {
        $sts_opts .= '; includeSubDomains';
      }
      $c->res->headers->strict_transport_security($sts_opts);
    }
  });
  Bugzilla::WebService::Server::REST->preload;

  $self->setup_routes;

  Bugzilla::Hook::process('app_startup', {app => $self});
}

sub setup_routes {
  my ($self) = @_;

  my $r = $self->routes;
  Bugzilla::App::CGI->setup_routes($r);
  Bugzilla::App::Main->setup_routes($r);
  Bugzilla::App::API->setup_routes($r);
  Bugzilla::App::SES->setup_routes($r);
  Bugzilla::App::OAuth2::Clients->setup_routes($r);

  $r->static_file('/__lbheartbeat__');
  $r->static_file(
    '/__version__' => {file => 'version.json', content_type => 'application/json'});
  $r->static_file('/version.json', {content_type => 'application/json'});

  $r->page('/review',        'splinter.html');
  $r->page('/user_profile',  'user_profile.html');
  $r->page('/userprofile',   'user_profile.html');
  $r->page('/request_defer', 'request_defer.html');
}

1;
