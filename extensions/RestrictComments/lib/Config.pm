# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::RestrictComments::Config;

use strict;
use warnings;

use Bugzilla::Config::Common;
use Bugzilla::Group;

our $sortkey = 510;

sub get_param_list {
    my ($class) = @_;

    my @param_list = (
        {
            name => 'restrict_comments_group',
            type => 's',
            choices => \&_get_all_group_names,
            default => '',
            checker => \&check_group
        },
        {
            name => 'restrict_comments_enable_group',
            type => 's',
            choices => \&_get_all_group_names,
            default => '',
            checker => \&check_group
        },
    );

    return @param_list;
}

sub _get_all_group_names {
    my @group_names = map {$_->name} Bugzilla::Group->get_all;
    unshift(@group_names, '');
    return \@group_names;
}

1;
