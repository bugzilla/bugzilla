#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE}     = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams (password_complexity => 'no_constraints');

use Test2::V0;
use Test2::Tools::Mock qw(mock mock_accessor);
use Try::Tiny;

use Bugzilla;
BEGIN { Bugzilla->extensions }

can_ok('Bugzilla::Extension::BMO', '_inject_headers_into_body');

my $User = mock 'Bugzilla::User' => (
  add_constructor => [fake_new => 'ref_copy'],
  override        => [
    settings => mock_accessor('settings'),
    new      => sub {
      my ($class, $ref) = @_;
      my $self = $class->fake_new($ref);
      $self->settings({headers_in_body => {value => 'on'}});
      return $self;
    },
  ],
);

my @fields = ('Triage Owner', 'Pants');

foreach my $field (@fields) {
  my $email = mock {} => (
    add => [
    parts => sub { 2 },
      header_pairs => sub {
        return ('X-Bugzilla-Changed-Fields' => $field);
      }
    ]
  );
  try {
    local $SIG{ALRM} = sub { die "caught in a loop" };
    alarm(5);
    Bugzilla::Extension::BMO::_inject_headers_into_body($email);
    alarm(0);
    pass("Did not get stuck with $field");
  }
  catch {
    fail("Got stuck with $field");
  };
}


done_testing;
