# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::User::Setting::Donation;

use 5.14.0;
use strict;
use warnings;

use base qw(Bugzilla::User::Setting);

use Bugzilla::Error;
use Bugzilla::Util qw(trick_taint validate_date);

sub validate_value {
  my ($self, $value) = @_;
  my $name = $self->{'_setting_name'};

  if ($name eq 'donate_banner_pref') {
    return $self->SUPER::validate_value($value);
  }

  if ($name eq 'donate_banner_last_version') {
    if ($value =~ /^0$|^[0-9A-Za-z][0-9A-Za-z._+-]*$/) {
      trick_taint($value);
      return;
    }
  }
  elsif ($name eq 'donate_banner_reminder_date') {
    if ($value eq '1970-01-01' || validate_date($value)) {
      trick_taint($value);
      return;
    }
  }

  ThrowCodeError('setting_value_invalid', {name => $name, value => $value});
}

1;

__END__

=head1 NAME

Bugzilla::User::Setting::Donation - Donation banner user settings

=cut