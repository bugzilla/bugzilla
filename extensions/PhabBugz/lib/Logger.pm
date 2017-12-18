# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::PhabBugz::Logger;

use 5.10.1;

use Moo;

use Bugzilla::Extension::PhabBugz::Constants;

has 'debugging' => ( is => 'ro' );

sub info  { shift->_log_it('INFO', @_) }
sub error { shift->_log_it('ERROR', @_) }
sub debug { shift->_log_it('DEBUG', @_) }

sub _log_it {
    my ($self, $method, $message) = @_;

    return if $method eq 'DEBUG' && !$self->debugging;
    chomp $message;
    if ($ENV{MOD_PERL}) {
        require Apache2::Log;
        Apache2::ServerRec::warn("FEED $method: $message");
    } elsif ($ENV{SCRIPT_FILENAME}) {
        print STDERR "FEED $method: $message\n";
    } else {
        print STDERR '[' . localtime(time) ."] $method: $message\n";
    }
}

1;
