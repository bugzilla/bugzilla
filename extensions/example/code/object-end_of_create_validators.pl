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
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>

use strict;
use warnings;
use Bugzilla;

my $args = Bugzilla->hook_args;
my $class = $args->{'class'};
my $params = $args->{'params'};

# Note that this is a made-up class, for this example.
if ($class->isa('Bugzilla::ExampleObject')) {
    # Always set example_field to 1, even if the validators said otherwise.
    $params->{example_field} = 1;
}

