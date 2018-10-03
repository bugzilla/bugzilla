# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::Plugin::Glue;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin';

use Try::Tiny;
use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::RNG ();
use Bugzilla::Util qw(with_writable_database);
use Mojo::Util qw(secure_compare);
use Mojo::JSON qw(decode_json);
use Scalar::Util qw(blessed);
use Scope::Guard;

sub register {
  my ($self, $app, $conf) = @_;

  my %D;
  if ($ENV{BUGZILLA_HTTPD_ARGS}) {
    my $args = decode_json($ENV{BUGZILLA_HTTPD_ARGS});
    foreach my $arg (@$args) {
      if ($arg =~ /^-D(\w+)$/) {
        $D{$1} = 1;
      }
      else {
        die "Unknown httpd arg: $arg";
      }
    }
  }

  $app->hook(
    before_dispatch => sub {
      my ($c) = @_;
      if ($D{HTTPD_IN_SUBDIR}) {
        my $path = $c->req->url->path;
        if ($path =~ s{^/bmo}{}s) {
          $c->stash->{bmo_prefix} = 1;
          $c->req->url->path($path);
        }
      }
      Log::Log4perl::MDC->put(request_id => $c->req->request_id);
      $c->stash->{cleanup_guard} = Scope::Guard->new(\&Bugzilla::cleanup);
      Bugzilla->usage_mode(USAGE_MODE_MOJO);
    }
  );

  $app->secrets([Bugzilla->localconfig->{side_wide_secret}]);

  $app->renderer->add_handler(
    'bugzilla' => sub {
      my ($renderer, $c, $output, $options) = @_;

      my %params;

      # Helpers
      foreach my $method (grep {m/^\w+\z/} keys %{$renderer->helpers}) {
        my $sub = $renderer->helpers->{$method};
        $params{$method} = sub { $c->$sub(@_) };
      }

      # Stash values
      $params{$_} = $c->stash->{$_} for grep {m/^\w+\z/} keys %{$c->stash};

      $params{self} = $params{c} = $c;

      my $name = sprintf '%s.%s.tmpl', $options->{template}, $options->{format};
      my $template = Bugzilla->template;
      $template->process($name, \%params, $output) or die $template->error;
    }
  );
  $app->helper(
    'bugzilla.login_redirect_if_required' => sub {
      my ($c, $type) = @_;

      if ($type == LOGIN_REQUIRED) {
        $c->redirect_to('/login');
        return undef;
      }
      else {
        return Bugzilla->user;
      }
    }
  );
  $app->helper(
    'bugzilla.login' => sub {
      my ($c, $type) = @_;
      $type //= LOGIN_NORMAL;

      return Bugzilla->user if Bugzilla->user->id;

      $type = LOGIN_REQUIRED
        if $c->param('GoAheadAndLogIn') || Bugzilla->params->{requirelogin};

      # Allow templates to know that we're in a page that always requires
      # login.
      if ($type == LOGIN_REQUIRED) {
        Bugzilla->request_cache->{page_requires_login} = 1;
      }

      my $login_cookie = $c->cookie("Bugzilla_logincookie");
      my $user_id      = $c->cookie("Bugzilla_login");
      my $ip_addr      = $c->tx->remote_address;

      return $c->bugzilla->login_redirect_if_required($type)
        unless ($login_cookie && $user_id);

      my $db_cookie = Bugzilla->dbh->selectrow_array(
        q{
                    SELECT cookie
                      FROM logincookies
                     WHERE cookie = ?
                           AND userid = ?
                           AND (restrict_ipaddr = 0 OR ipaddr = ?)
                }, undef, ($login_cookie, $user_id, $ip_addr)
      );

      if (defined $db_cookie && secure_compare($login_cookie, $db_cookie)) {
        my $user = Bugzilla::User->check({id => $user_id, cache => 1});

        # If we logged in successfully, then update the lastused
        # time on the login cookie
        with_writable_database {
          Bugzilla->dbh->do(
            q{ UPDATE logincookies SET lastused = NOW() WHERE cookie = ? },
            undef, $login_cookie);
        };
        Bugzilla->set_user($user);
        return $user;
      }
      else {
        return $c->bugzilla->login_redirect_if_required($type);
      }
    }
  );
  $app->helper(
    'bugzilla.error_page' => sub {
      my ($c, $error) = @_;
      if (blessed $error && $error->isa('Bugzilla::Error::Base')) {
        $c->render(
          handler  => 'bugzilla',
          template => $error->template,
          error    => $error->message,
          %{$error->vars}
        );
      }
      else {
        $c->reply->exception($error);
      }
    }
  );

  $app->log(MojoX::Log::Log4perl::Tiny->new(
    logger => Log::Log4perl->get_logger(ref $app)
  ));
}

1;
