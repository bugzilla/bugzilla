# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::App::Command::move_flag_types;   ## no critic (Capitalization)
use Mojo::Base 'Mojolicious::Command';

use Bugzilla::Constants;
use Mojo::File 'path';
use Mojo::Util 'getopt';
use JSON::MaybeXS;

has description => 'Move flag types';
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;
  my $doit = 0;
  my ($oldid, $newid, $product, $component, $debug);

  Bugzilla->usage_mode(USAGE_MODE_CMDLINE);
  getopt \@args,
    'old-id|o=s'    => \$oldid,
    'new-id|n=s'    => \$newid,
    'product|p=s'   => \$product,
    'component|c=s' => \$component,
    'doit|d'        => \$doit,
    'debug|D'       => \$debug;

  die $self->usage unless $oldid && $newid && $product;

  my $model = Bugzilla->dbh->model;

  my $old_flagtype = $model->resultset('FlagType')->find({id => $oldid})
    or die "No flagtype $oldid";
  my $new_flagtype = $model->resultset('FlagType')->find({id => $newid})
    or die "No flagtype $newid";

  my $bugs  = $model->resultset('Bug')->search(_bug_query($product, $component));
  my $flags = $bugs->search_related('flags', {'flags.type_id' => $oldid});
  my $count = $flags->count;

  if ($debug) {
    my $query = ${ $flags->as_query };
    say STDERR "SQL query:\n", JSON::MaybeXS->new(pretty => 1, canonical => 1)->encode($query);
  }
  if ($count) {
    my $old_name = $old_flagtype->name;
    my $new_name = $new_flagtype->name;
    say "Moving '$count' flags from $old_name ($oldid) to $new_name ($newid)...";

    if (!$doit) {
      say
        "Pass the argument --doit or -d to permanently make changes to the database.";
    }
    else {
      while (my $flag = $flags->next) {
        $model->txn_do(sub {
          $flag->type_id($new_flagtype->id);
          $flag->update();
        });
        say "Bug: ", $flag->bug_id, " Flag: ", $flag->id;
      }
    }

    # It's complex to determine which items now need to be flushed from memcached.
    # As this is expected to be a rare event, we just flush the entire cache.
    Bugzilla->memcached->clear_all();
  }
  else {
    say "No flags to move";
  }
}

sub _bug_query {
  my ($product, $component) = @_;

  # if we have a component name, search on product and component name
  if ($component) {
    return ({'product.name' => $product, 'component.name' => $component},
      {join => {component => 'product'}});
  }
  else {
    return ({'product.name' => $product}, {join => 'product'});
  }
}

1;

__END__

=head1 NAME

Bugzilla::App::Command::move_flag_types - Move currently set flags from one type id to another based
on product and optionally component.

=head1 SYNOPSIS

  Usage: APPLICATION move_flag_types

    ./bugzilla.pl move_flag_types --old-id 4 --new-id 720 --product Firefox --component Installer

  Options:
    -h, --help               Print a brief help message and exits.
    -o, --oldid type_id      Old flag type id. Use editflagtypes.cgi to determine the type id from the URL.
    -n, --newid type_id      New flag type id. Use editflagtypes.cgi to determine the type id from the URL.
    -p, --product name       The product that the bugs most be assigned to.
    -c, --component name     (Optional) The component of the given product that the bugs must be assigned to.
    -d, --doit               Without this argument, changes are not actually committed to the database.
    -D, --debug              Show the SQL query

=head1 DESCRIPTION

This command will move bugs matching a specific product (and optionally a component)
from one flag type id to another if the bug has the flag set to either +, -, or ?.

=head1 ATTRIBUTES

L<Bugzilla::App::Command::move_flag_types> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $move_flag_types->description;
  $move_flag_types        = $move_flag_types->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $move_flag_types->usage;
  $move_flag_types  = $move_flag_types->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Bugzilla::App::Command::move_flag_types> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $move_flag_types->run(@ARGV);

Run this command.
