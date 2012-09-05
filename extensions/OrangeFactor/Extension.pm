# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::OrangeFactor;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::User::Setting;
use Bugzilla::Constants;
use Bugzilla::Attachment;

our $VERSION = '1.0';

sub template_before_process {
    my ($self, $args) = @_;
    my $file = $args->{'file'};
    my $vars = $args->{'vars'};

    my $user = Bugzilla->user;

    return unless $user && $user->id && $user->settings;
    return unless $user->settings->{'orange_factor'}->{'value'} eq 'on';

    # in the header we just need to set the var, to 
    # ensure the css and javascript get included
    if ($file eq 'bug/show-header.html.tmpl'
        || $file eq 'bug/edit.html.tmpl') {
        my $bug = exists $vars->{'bugs'} ? $vars->{'bugs'}[0] : $vars->{'bug'};
        if ($bug && $bug->status_whiteboard =~ /\[orange\]/) {
            $vars->{'orange_factor'} = 1;
        }
    }
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    add_setting('orange_factor', ['on', 'off'], 'off');
}

__PACKAGE__->NAME;
