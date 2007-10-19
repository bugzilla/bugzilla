use strict;
use warnings;
use Bugzilla;
my $dispatch = Bugzilla->hook_args->{dispatch};
$dispatch->{Example} = "extensions::example::lib::WSExample";
