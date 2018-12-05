# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.


=head1 NAME

Bugzilla::Extension::Example::Migrate::ImportBugs - Bugzilla example bug importer

=head1 DESCRIPTION

This is not a complete implementation of a Import module.  For a working
implementation see L<Bugzilla::Migrate::Gnats>.

=cut

package Bugzilla::Extension::Example::Migrate::ImportBugs;

use 5.14.0 use strict;
use warnings;

use parent qw(Bugzilla::Migrate);

use Bugzilla::Constants;
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::Util qw(format_time trim generate_random_password);

use constant REQUIRED_MODULES => [
  {
    package => 'Email-Simple-FromHandle',
    module  => 'Email::Simple::FromHandle',
    version => 0.050,
  },
];

use constant FIELD_MAP => {'Number' => 'bug_id', 'Category' => 'product',};

use constant VALUE_MAP => {
  bug_severity => {'serious'  => 'major',    'non-critical' => 'normal',},
  bug_status   => {'feedback' => 'RESOLVED', 'released'     => 'VERIFIED',},
};

use constant IMPORTBUGS_CONFIG_VARS => (
  {
    name    => 'default_email_domain',
    default => 'example.com',
    desc    => <<'END',
# Some users do not have full email addresses, but Bugzilla requires
# every user to have an email address. What domain should be appended to
# usernames that don't have emails, to make them into email addresses?
# (For example, if you leave this at the default, "unknown" would become
# "unknown@example.com".)
END
  },
);

#########
# Hooks #
#########

sub before_insert {
  my $self = shift;
}

#########
# Users #
#########

sub _read_users {
  my $self = shift;
}

############
# Products #
############

sub _read_products {
  my $self = shift;
}

################
# Reading Bugs #
################

sub _read_bugs {
  my $self = shift;
}

sub _parse_project {
  my ($self, $directory) = @_;
}

1;
