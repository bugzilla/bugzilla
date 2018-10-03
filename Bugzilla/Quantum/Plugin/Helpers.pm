# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Quantum::Plugin::Helpers;
use 5.10.1;
use Mojo::Base qw(Mojolicious::Plugin);

use Bugzilla::Logging;
use Carp;

sub register {
  my ($self, $app, $conf) = @_;

  $app->helper(
    basic_auth => sub {
      my ($c, $realm, $auth_user, $auth_pass) = @_;
      my $req = $c->req;
      my ($user, $password) = $req->url->to_abs->userinfo =~ /^([^:]+):(.*)/;

      unless ($realm && $auth_user && $auth_pass) {
        croak 'basic_auth() called with missing parameters.';
      }

      unless ($user eq $auth_user && $password eq $auth_pass) {
        WARN('username and password do not match');
        $c->res->headers->www_authenticate("Basic realm=\"$realm\"");
        $c->res->code(401);
        $c->rendered;
        return 0;
      }

      return 1;
    }
  );
  $app->routes->add_shortcut(
    static_file => sub {
      my ($r, $path, $option) = @_;
      my $file         = $option->{file};
      my $content_type = $option->{content_type} // 'text/plain';
      unless ($file) {
        $file = $path;
        $file =~ s!^/!!;
      }

      return $r->get(
        $path => sub {
          my ($c) = @_;
          $c->res->headers->content_type($content_type);
          $c->reply->file($c->app->home->child($file));
        }
      );
    }
  );
  $app->routes->add_shortcut(
    page => sub {
      my ($r, $path, $id) = @_;

      return $r->any($path)->to('CGI#page_cgi' => {id => $id});
    }
  );
}

1;
