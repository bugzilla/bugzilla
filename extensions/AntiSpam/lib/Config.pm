# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::AntiSpam::Config;

use strict;
use warnings;

use Bugzilla::Config::Common;
use Bugzilla::Group;

our $sortkey = 511;

sub get_param_list {
    my ($class) = @_;

    my @param_list = (
        {
            name => 'antispam_spammer_exclude_group',
            type => 's',
            choices => \&_get_all_group_names,
            default => 'canconfirm',
            checker => \&check_group
        },
        {
            name => 'antispam_spammer_comment_count',
            type => 't',
            default => '3',
            checker => \&check_numeric
        },
        {
            name => 'antispam_spammer_disable_text',
            type => 'l',
            default =>
                "This account has been automatically disabled as a result of a " .
                "high number of spam comments.\n\nPlease contact the address at ".
                "the end of this message if you believe this to be an error."
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
