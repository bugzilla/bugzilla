# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Example::Config;

use 5.14.0;
use strict;
use warnings;

use Bugzilla::Config::Common;

our $sortkey = 5000;

sub get_param_list {
  my ($class) = @_;

  my @param_list = (
    {name => 'example_string', type => 't', default => 'Bugzilla is powerful'},
    {
      name    => 'example_constrained_string',
      type    => 't',
      default => '12-xfdd-5',
      checker => sub {
        $_[0] =~ /^\d{2}\-[a-zA-Z]{4}\-\d$/
          ? ''
          : "$_[0] must be of the form NN-XXXX-N";
      }
    },
    {
      name    => 'example_number',
      type    => 't',
      default => '905',
      checker => \&check_numeric
    },
    {name => 'example_password', type => 'p', default => '1234'},
    {
      name    => 'example_multi_lines',
      type    => 'l',
      default => "This text can be very long.\n\nVery very long!"
    },

    # Default can only be 0 or 1.
    {name => 'example_boolean', type => 'b', default => 0},
    {
      name    => 'example_single_select',
      type    => 's',
      choices => ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      default => 'Thursday',
      checker => \&check_multi
    },
    {
      name    => 'example_multi_select',
      type    => 'm',
      choices => ['Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn'],
      default => ['Venus', 'Saturn'],
      checker => \&check_multi
    },

    # This one lets you order selected items.
    {
      name    => 'example_multi_ordered',
      type    => 'o',
      choices => ['Perl', 'Python', 'PHP', 'C++', 'Java'],
      default => 'Perl,C++',
      checker => \&check_multi
    },
  );
  return @param_list;
}

1;
