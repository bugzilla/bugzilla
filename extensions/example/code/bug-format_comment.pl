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
# The Initial Developer of the Original Code is Canonical Ltd.
# Portions created by Canonical Ltd. are Copyright (C) 2009
# Canonical Ltd. All Rights Reserved.
#
# Contributor(s):
#   Max Kanat-Alexander <mkanat@bugzilla.org>


use strict;
use warnings;
use Bugzilla;
use Bugzilla::ExampleHook qw(replace_bar);

# This replaces every occurrence of the word "foo" with the word
# "bar"

my $regexes = Bugzilla->hook_args->{'regexes'};
push(@$regexes, { match => qr/\bfoo\b/, replace => 'bar' });

# And this links every occurrence of the word "bar" to example.com,
# but it won't affect "foo"s that have already been turned into "bar"
# above (because each regex is run in order, and later regexes don't modify
# earlier matches, due to some cleverness in Bugzilla's internals).
#
# For example, the phrase "foo bar" would become:
# bar <a href="http://example.com/bar">bar</a>
#
# See lib/Bugzilla/ExampleHook.pm in this extension for the code of 
# "replace_bar".
my $bar_match = qr/\b(bar)\b/;
push(@$regexes, { match => $bar_match, replace => \&replace_bar });
