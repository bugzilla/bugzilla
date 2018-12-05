# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::User::Session;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Object);

#####################################################################
# Overriden Constants that are used as methods
#####################################################################

use constant DB_TABLE   => 'logincookies';
use constant DB_COLUMNS => qw(
  cookie
  userid
  lastused
  ipaddr
  id
  restrict_ipaddr
);

use constant UPDATE_COLUMNS => qw();
use constant VALIDATORS     => {};
use constant LIST_ORDER     => 'lastused DESC';
use constant NAME_FIELD     => 'cookie';

# turn off auditing and exclude these objects from memcached
use constant {
  AUDIT_CREATES => 0,
  AUDIT_UPDATES => 0,
  AUDIT_REMOVES => 0,
  USE_MEMCACHED => 0
};

# Accessors
sub id              { return $_[0]->{id} }
sub userid          { return $_[0]->{userid} }
sub cookie          { return $_[0]->{cookie} }
sub lastused        { return $_[0]->{lastused} }
sub ipaddr          { return $_[0]->{ipaddr} }
sub restrict_ipaddr { return $_[0]->{restrict_ipaddr} }

1;
