# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);

use Test::More "no_plan";

use QA::Util;

my ($sel, $config) = get_selenium();

# Turn on 'requirelogin'.

log_in($sel, $config, 'admin');
set_parameters($sel, { "User Authentication" => {"requirelogin-on" => undef} });
logout($sel);

# We try to access each page. None of the ones listed below should
# let you view it without being logged in.

my @pages = qw(admin attachment buglist chart colchange describecomponents
               describekeywords duplicates editclassifications editcomponents
               editfields editflagtypes editgroups editkeywords editmilestones
               editparams editproducts editsettings editusers editvalues
               editversions editwhines editworkflow enter_bug long_list page
               post_bug process_bug query quips report reports request
               sanitycheck search_plugin show_activity show_bug showattachment
               showdependencygraph showdependencytree summarize_time
               userprefs votes xml);

foreach my $page (@pages) {
    $sel->open_ok("/$config->{bugzilla_installation}/${page}.cgi");
    if ($page ne 'votes' || $config->{test_extensions}) {
        $sel->title_is("Log in to Bugzilla");
    }
    else {
        $sel->title_is("Extension Disabled");
    }
}

# Those have parameters passed to the page, so we put them here separately.

@pages = ("query.cgi?format=report-table", "query.cgi?format=report-graph",
          "votes.cgi?action=show_user", "votes.cgi?action=show_bug");

foreach my $page (@pages) {
    $sel->open_ok("/$config->{bugzilla_installation}/$page");
    if ($page !~ /^votes/ || $config->{test_extensions}) {
        $sel->title_is("Log in to Bugzilla");
    }
    else {
        $sel->title_is("Extension Disabled");
    }
}

# These pages should still be accessible.

@pages = ("config.cgi", "createaccount.cgi", "index.cgi", "relogin.cgi",
          "token.cgi?a=reqpw&loginname=" . $config->{unprivileged_user_login});

foreach my $page (@pages) {
    $sel->open_ok("/$config->{bugzilla_installation}/$page");
    $sel->title_isnt("Log in to Bugzilla");
}

# Turn off 'requirelogin'.

log_in($sel, $config, 'admin');
set_parameters($sel, { "User Authentication" => {"requirelogin-off" => undef} });
logout($sel);

# Make sure we can access random pages again.
$sel->click_ok("link=Search");
$sel->wait_for_page_to_load_ok(WAIT_TIME);
$sel->title_isnt("Log in to Bugzilla");
