# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::QA;

use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::QA::Util;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util;
use Bugzilla::Bug;
use Bugzilla::User;

our $VERSION = '1.0';

sub page_before_template {
    my ($self, $args) = @_;
    return if $args->{page_id} ne 'qa/email_in.html';

    my $template = Bugzilla->template;
    my $cgi = Bugzilla->cgi;
    print $cgi->header;

    # Needed to make sure he can access and edit bugs.
    my $user = Bugzilla::User->check($cgi->param('sender'));
    Bugzilla->set_user($user);

    my ($output, $tmpl_file);
    my $action = $cgi->param('action') || '';
    my $vars = { sender => $user, action => $action, pid => $$ };

    if ($action eq 'create') {
        $tmpl_file = 'qa/create_bug.txt.tmpl';
    }
    elsif ($action eq 'create_with_headers') {
        $tmpl_file = 'qa/create_bug_with_headers.txt.tmpl';
    }
    elsif ($action =~ /^update(_with_headers)?$/) {
        my $f = $1 || '';
        $tmpl_file = "qa/update_bug$f.txt.tmpl";
        my $bug = Bugzilla::Bug->check($cgi->param('bug_id'));
        $vars->{bug_id} = $bug->id;
    }
    else {
        ThrowUserError('unknown_action', { action => $action });
    }

    $template->process($tmpl_file, $vars, \$output)
      or ThrowTemplateError($template->error());

    my $file = "/tmp/email_in_$$.txt";
    open(FH, '>', $file);
    print FH $output;
    close FH;

    $output = `email_in.pl -v < $file 2>&1`;
    unlink $file;

    parse_output($output, $vars);

    $template->process('qa/results.html.tmpl', $vars)
      or ThrowTemplateError($template->error());
}

__PACKAGE__->NAME;
