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
# The Initial Developer of the Original Code is ITA Softwware.
# Portions created by the Initial Developer are Copyright (C) 2009
# the Initial Developer. All Rights Reserved.
#
# Contributor(s): Bradley Baetz <bbaetz@everythingsolved.com>

use strict;

my $dbh = Bugzilla->dbh;
my $sth;

my $status = Bugzilla->hook_args->{'status'};

# Check that all users are Australian
$status->('example_check_au_user');

my $sth = $dbh->prepare("SELECT userid, login_name
                           FROM profiles
                          WHERE login_name NOT LIKE '%.au'");
$sth->execute;

my $seen_nonau = 0;
while (my ($userid, $login, $numgroups) = $sth->fetchrow_array) {
    $status->('example_check_au_user_alert',
              { userid => $userid, login => $login },
              'alert');
    $seen_nonau = 1;
}

$status->('example_check_au_user_prompt') if $seen_nonau;
