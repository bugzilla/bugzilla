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
# The Initial Developer of the Original Code is ITA Software
# Portions created by the Initial Developer are Copyright (C) 2009 
# the Initial Developer. All Rights Reserved.
#
# Contributor(s): 
#   Max Kanat-Alexander <mkanat@bugzilla.org>

use strict;
use warnings;
use Bugzilla;
use Data::Dumper;

# This code doesn't actually *do* anything, it's just here to show you
# how to use this hook.
my $params = Bugzilla->hook_args->{'params'};

# Uncomment this line below to see a line in your webserver's error log
# containing all validated bug field values every time you file a bug.
# warn Dumper($params);

# This would remove all ccs from the bug, preventing ANY ccs from being
# added on bug creation.
# $params->{cc} = [];
