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
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developer are Copyright (C) 2009 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s): 
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::ExampleHook;
use strict;
use base qw(Exporter);
our @EXPORT_OK = qw(
    replace_bar
);

use Bugzilla::Util qw(html_quote);

# Used by bug-format_comment--see its code for an explanation.
sub replace_bar {
    my $params = shift;
    # $match is the first parentheses match in the $bar_match regex 
    # in bug-format_comment.pl. We get up to 10 regex matches as 
    # arguments to this function.
    my $match = $params->{matches}->[0];
    # Remember, you have to HTML-escape any data that you are returning!
    $match = html_quote($match);
    return qq{<a href="http://example.com/">$match</a>};
};

1;
