# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Bitly;
use strict;
use warnings;

use base qw(Bugzilla::Extension);
our $VERSION = '1';

use Bugzilla;

sub webservice {
    my ($self,  $args) = @_;
    $args->{dispatch}->{Bitly} = "Bugzilla::Extension::Bitly::WebService";
}

sub config_modify_panels {
    my ($self, $args) = @_;
    push @{ $args->{panels}->{advanced}->{params} }, {
        name    => 'bitly_token',
        type    => 't',
        default => '',
    };
}

__PACKAGE__->NAME;
