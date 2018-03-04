# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Option;

use 5.10.1;
use strict;
use warnings;

use base 'Bugzilla::Object';

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Util;

#
# initialisation
#

use constant DB_TABLE => 'push_options';
use constant DB_COLUMNS => qw(
    id
    connector
    option_name
    option_value
);
use constant UPDATE_COLUMNS => qw(
    option_value
);
use constant VALIDATORS => {
    connector => \&_check_connector,
};
use constant LIST_ORDER => 'connector';
use constant NAME_FIELD => 'option_name';
#
# accessors
#
use Class::XSAccessor {
    accessors => {
        id   => __PACKAGE__->ID_FIELD,
        name => __PACKAGE__->NAME_FIELD,
    },
};

sub connector { return $_[0]->{'connector'};    }
sub value     { return $_[0]->{'option_value'}; }

#
# mutators
#

sub set_value { $_[0]->{'option_value'} = $_[1]; }

#
# validators
#

sub _check_connector {
    my ($invocant, $value) = @_;
    $value eq '*'
        || $value eq 'global'
        || Bugzilla->push_ext->connectors->exists($value)
        || ThrowCodeError('push_invalid_connector');
    return $value;
}

1;

