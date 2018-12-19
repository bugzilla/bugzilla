# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::Command::revoke_api_keys; ## no critic (Capitalization)
use 5.10.1;
use Mojo::Base 'Mojolicious::Command';

use Bugzilla::Constants;
use Bugzilla::User::APIKey;
use Mojo::File 'path';
use Mojo::Util 'getopt';
use PerlX::Maybe 'maybe';

has description => 'Revoke api keys';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;
  my ($app_id, $description);

  Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
  getopt \@args,
    'a|app-id=s'         => \$app_id,
    'd|description-id=s' => \$description;
  die $self->usage unless $app_id || $description;

  my $query = {
    revoked => 0,
    maybe(app_id => $app_id), maybe(description => $description)
  };
  my $keys = Bugzilla::User::APIKey->match($query);
  foreach my $key (@$keys) {
    say 'Updating ', $key->id;
    $key->set_revoked(1);
    $key->update();
  }
}

1;
__END__
=encoding utf8

=head1 NAME

Bugzilla::Quantum::Command::revoke_api_keys - revoke API keys command

=head1 SYNOPSIS

  Usage: APPLICATION revoke_api_keys [OPTIONS]

    mojo revoke_api_keys -a deadbeef

  Options:
    -h, --help                  Show this summary of available options
    -a, --app-id app_id         Match against a specific app_id
    -d, --description desc      Match against a specific description

=head1 DESCRIPTION

L<Bugzilla::Quantum::Command::revoke_api_keys> revokes API keys.

=head1 ATTRIBUTES

L<Bugzilla::Quantum::Command::revoke_api_keys> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $revoke_api_keys->description;
  $revoke_api_keys        = $revoke_api_keys->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $revoke_api_keys->usage;
  $revoke_api_keys  = $revoke_api_keys->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Bugzilla::Quantum::Command::revoke_api_keys> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $revoke_api_keys->run(@ARGV);

Run this command.

=cut
