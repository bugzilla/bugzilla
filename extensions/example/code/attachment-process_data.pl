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
# The Original Code is the Bugzilla Example Plugin.
#
# The Initial Developer of the Original Code is Frédéric Buclin.
# Portions created by Frédéric Buclin are Copyright (C) 2009
# Frédéric Buclin. All Rights Reserved.
#
# Contributor(s): Frédéric Buclin <LpSolit@gmail.com>

use strict;
use warnings;

use Bugzilla;
my $args = Bugzilla->hook_args;

my $type = $args->{attributes}->{mimetype};
my $filename = $args->{attributes}->{filename};

# Make sure images have the correct extension.
# Uncomment the two lines below to make this check effective.
if ($type =~ /^image\/(\w+)$/) {
    my $format = $1;
    if ($filename =~ /^(.+)(:?\.[^\.]+)$/) {
        my $name = $1;
#        $args->{attributes}->{filename} = "${name}.$format";
    }
    else {
        # The file has no extension. We append it.
#        $args->{attributes}->{filename} .= ".$format";
    }
}
