use Cache::Memcached::Fast;
use Devel::Peek;

my $mc = Cache::Memcached::Fast->new( { servers => ['127.0.0.1:11211'] });

my $v=[$ENV{PATH}];

Dump($v->[0]);

$mc->set("taint", $v);

Dump($v->[0]);

Dump($mc->get("taint")->[0]);
