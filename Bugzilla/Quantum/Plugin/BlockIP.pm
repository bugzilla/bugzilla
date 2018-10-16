package Bugzilla::Quantum::Plugin::BlockIP;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin';

use Bugzilla::Memcached;

use constant BLOCK_TIMEOUT => 60 * 60;

my $MEMCACHED = Bugzilla::Memcached->new()->{memcached};

sub register {
  my ($self, $app, $conf) = @_;

  $app->hook(before_routes => \&_before_routes);
  $app->helper(block_ip   => \&_block_ip);
  $app->helper(unblock_ip => \&_unblock_ip);
}

sub _block_ip {
  my ($class, $ip) = @_;
  $MEMCACHED->set("block_ip:$ip" => 1, BLOCK_TIMEOUT) if $MEMCACHED;
}

sub _unblock_ip {
  my ($class, $ip) = @_;
  $MEMCACHED->delete("block_ip:$ip") if $MEMCACHED;
}

sub _before_routes {
  my ($c) = @_;
  return if $c->stash->{'mojo.static'};

  my $ip = $c->tx->remote_address;
  if ($MEMCACHED && $MEMCACHED->get("block_ip:$ip")) {
    $c->block_ip($ip);
    $c->res->code(429);
    $c->res->message('Too Many Requests');
    $c->render(handler => 'bugzilla', template => 'global/ip-blocked', block_timeout => BLOCK_TIMEOUT);
  }
}

1;
