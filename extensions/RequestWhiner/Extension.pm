# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the RequestWhiner Bugzilla Extension.
#
# The Initial Developer of the Original Code is the Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Gervase Markham <written.to.the.glory.of.god@gerv.net>

package Bugzilla::Extension::RequestWhiner;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Constants qw(bz_locations);
use Bugzilla::Install::Filesystem;

our $VERSION = '0.01';

sub install_filesystem {
    my ($self, $args) = @_;
    my $files = $args->{'files'};

    my $extensionsdir = bz_locations()->{'extensionsdir'};
    my $scriptname = $extensionsdir . "/" . __PACKAGE__->NAME . "/bin/whineatrequests.pl";
    
    $files->{$scriptname} = { 
        perms => Bugzilla::Install::Filesystem::WS_EXECUTE
    };
}

__PACKAGE__->NAME;
