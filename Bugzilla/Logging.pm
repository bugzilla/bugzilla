# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Logging;
use 5.10.1;
use strict;
use warnings;

use Log::Log4perl;
use Log::Log4perl::MDC;
use File::Spec::Functions qw(rel2abs);
use Bugzilla::Constants qw(bz_locations);

BEGIN {
    my $file = $ENV{LOG4PERL_CONFIG_FILE} // "log4perl-syslog.conf";
    Log::Log4perl::Logger::create_custom_level('NOTICE', 'WARN', 5, 2);
    Log::Log4perl->init(rel2abs($file, bz_locations->{confdir}));
    Log::Log4perl->get_logger(__PACKAGE__)->debug("logging enabled in $0");
}

1;
