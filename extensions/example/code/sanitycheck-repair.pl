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
# The Initial Developer of the Original Code is ITA Software.
# Portions created by the Initial Developer are Copyright (C) 2009
# the Initial Developer. All Rights Reserved.
#
# Contributor(s): Bradley Baetz <bbaetz@everythingsolved.com>

use strict;

use Bugzilla;

my $cgi = Bugzilla->cgi;
my $dbh = Bugzilla->dbh;

my $status = Bugzilla->hook_args->{'status'};

if ($cgi->param('example_repair_au_user')) {
    $status->('example_repair_au_user_start');

    #$dbh->do("UPDATE profiles
    #             SET login_name = CONCAT(login_name, '.au')
    #           WHERE login_name NOT LIKE '%.au'");

    $status->('example_repair_au_user_end');
}
