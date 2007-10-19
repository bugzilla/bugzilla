package extensions::example::lib::WSExample;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

# This can be called as Example.hello() from XML-RPC.
sub hello { return 'Hello!'; }

1;
