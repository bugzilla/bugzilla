# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::LogEntry;

use strict;
use warnings;

use base 'Bugzilla::Object';

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Extension::Push::Constants;

#
# initialisation
#

use constant DB_TABLE => 'push_log';
use constant DB_COLUMNS => qw(
    id
    message_id
    change_set
    routing_key
    connector
    push_ts
    processed_ts
    result
    data
);
use constant VALIDATORS => {
    data => \&_check_data,
};
use constant NAME_FIELD => '';
use constant LIST_ORDER => 'processed_ts DESC';

#
# accessors
#

sub message_id   { return $_[0]->{'message_id'};   }
sub change_set   { return $_[0]->{'change_set'};   }
sub routing_key  { return $_[0]->{'routing_key'};  }
sub connector    { return $_[0]->{'connector'};    }
sub push_ts      { return $_[0]->{'push_ts'};      }
sub processed_ts { return $_[0]->{'processed_ts'}; }
sub result       { return $_[0]->{'result'};       }
sub data         { return $_[0]->{'data'};         }

sub result_string { return push_result_to_string($_[0]->result) }

#
# validators
#

sub _check_data {
    my ($invocant, $value) = @_;
    return $value eq '' ? undef : $value;
}

1;

