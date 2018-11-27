# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Task;
use 5.10.1;
use Moo::Role;

use Bugzilla::Constants;
use Bugzilla::Logging;
use Bugzilla::Types qw(User);
use Types::Standard qw(Str);
use Type::Utils;
use Scalar::Util qw(blessed);
use Mojo::Util qw(decamelize);
use Try::Tiny;
use Capture::Tiny qw(capture_stdout);

requires 'prepare', 'run', 'subject', '_build_estimated_duration';

my $Duration = class_type { class => 'DateTime::Duration' };

has 'user' => (is => 'ro',   isa => User, required => 1);
has 'name' => (is => 'lazy', isa => Str,  init_arg => undef);
has 'estimated_duration' => (is => 'lazy', isa => $Duration, init_arg => undef);

around 'run' => sub {
  my ($original_method, $self, @args) = @_;
  my $scope = Bugzilla->set_user($self->user, scope_guard => 1);
  Bugzilla->error_mode(ERROR_MODE_MOJO);
  my $result;
  try {
    my $stdout = capture_stdout {
      $result = $self->$original_method(@args);
    };
    if ($stdout) {
      FATAL("$self sent output to STDOUT: $stdout");
    }
  }
  catch {
    $result = {error => $_};
  };
  return $result;
};

sub _build_name {
  my ($self) = @_;
  my $class  = blessed($self);
  my $pkg    = __PACKAGE__;
  $class =~ s/^\Q$pkg\E:://;
  return decamelize($class);
}

1;
