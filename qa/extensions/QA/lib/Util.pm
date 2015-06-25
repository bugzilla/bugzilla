# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::QA::Util;

use strict;
use base qw(Exporter);

our @EXPORT = qw(
    parse_output
);

sub parse_output {
    my ($output, $vars) = @_;

    $vars->{error} = ($output =~ /software error/i) ? 1 : 0;
    $vars->{output} = $output;
    $vars->{bug_id} ||= ($output =~ /Created bug (\d+)/i) ? $1 : undef;
}

1;
