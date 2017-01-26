#!/usr/bin/perl -T
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::User;
use Bugzilla::Keyword;
use Bugzilla::Bug;
use Bugzilla::Hook;
use Bugzilla::CGI;
use Bugzilla::Util qw(detaint_natural);

my $cgi = Bugzilla->cgi;
my $template = Bugzilla->template;
my $vars = {};

my $user = Bugzilla->login();

# BMO: add show_bug_format for experimental UI work
my $format_params = {
    format => scalar $cgi->param('format'),
    ctype  => scalar $cgi->param('ctype'),
};
Bugzilla::Hook::process('show_bug_format', $format_params);
my $format = $template->get_format("bug/show",
                                   $format_params->{format},
                                   $format_params->{ctype});

# Editable, 'single' HTML bugs are treated slightly specially in a few places
my $single = (!$format->{format} || $format->{format} ne 'multiple')
             && $format->{extension} eq 'html';

# If we don't have an ID, _AND_ we're only doing a single bug, then prompt
if (!$cgi->param('id') && $single) {
    print Bugzilla->cgi->header();
    $template->process("bug/choose.html.tmpl", $vars) ||
      ThrowTemplateError($template->error());
    exit;
}

if ($format_params->{format} eq 'modal') {
    my $bug_id = $cgi->param('id');
    detaint_natural($bug_id);
    $cgi->content_security_policy(Bugzilla::CGI::SHOW_BUG_MODAL_CSP($bug_id));
}


my @bugs;
my %marks;

# If the user isn't logged in, we use data from the shadow DB. If he plans
# to edit the bug(s), he will have to log in first, meaning that the data
# will be reloaded anyway, from the main DB.
Bugzilla->switch_to_shadow_db unless $user->id;

if ($single) {
    my $id = $cgi->param('id');
    push @bugs, Bugzilla::Bug->check({ id => $id, cache => 1 });
    if (defined $cgi->param('mark')) {
        foreach my $range (split ',', $cgi->param('mark')) {
            if ($range =~ /^(\d+)-(\d+)$/) {
               foreach my $i ($1..$2) {
                   $marks{$i} = 1;
               }
            } elsif ($range =~ /^(\d+)$/) {
               $marks{$1} = 1;
            }
        }
    }
} else {
    foreach my $id ($cgi->param('id')) {
        # Be kind enough and accept URLs of the form: id=1,2,3.
        my @ids = split(/,/, $id);
        foreach my $bug_id (@ids) {
            my $bug = new Bugzilla::Bug({ id => $bug_id, cache => 1 });
            # This is basically a backwards-compatibility hack from when
            # Bugzilla::Bug->new used to set 'NotPermitted' if you couldn't
            # see the bug.
            if (!$bug->{error} && !$user->can_see_bug($bug->bug_id)) {
                $bug->{error} = 'NotPermitted';
            }
            push(@bugs, $bug);
        }
    }
}

Bugzilla::Bug->preload(\@bugs);

$vars->{'bugs'} = \@bugs;
$vars->{'marks'} = \%marks;

my @bugids = map {$_->bug_id} grep {!$_->error} @bugs;
$vars->{'bugids'} = join(", ", @bugids);

# Work out which fields we are displaying (currently XML only.)
# If no explicit list is defined, we show all fields. We then exclude any
# on the exclusion list. This is so you can say e.g. "Everything except 
# attachments" without listing almost all the fields.
my @fieldlist = (Bugzilla::Bug->fields, 'flag', 'group', 'long_desc',
                 'attachment', 'attachmentdata', 'token');
my %displayfields;

if ($cgi->param("field")) {
    @fieldlist = $cgi->param("field");
}

unless (Bugzilla->user->is_timetracker) {
    @fieldlist = grep($_ !~ /(^deadline|_time)$/, @fieldlist);
}

foreach (@fieldlist) {
    $displayfields{$_} = 1;
}

foreach ($cgi->param("excludefield")) {
    $displayfields{$_} = undef;    
}

$vars->{'displayfields'} = \%displayfields;

if ($user->id) {
    foreach my $bug_id (@bugids) {
        Bugzilla->log_user_request($bug_id, undef, 'bug-get');
    }
}
print $cgi->header($format->{'ctype'});

$template->process($format->{'template'}, $vars)
  || ThrowTemplateError($template->error());
