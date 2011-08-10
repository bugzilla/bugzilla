# ***** BEGIN LICENSE BLOCK *****
# Version: MPL 1.1/GPL 2.0/LGPL 2.1
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# The Original Code is the BzAPI Bugzilla Extension.
#
# The Initial Developer of the Original Code is
# the Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2010
# the Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Gervase Markham <gerv@gerv.net>
#
# Alternatively, the contents of this file may be used under the terms of
# either the GNU General Public License Version 2 or later (the "GPL"), or
# the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
# in which case the provisions of the GPL or the LGPL are applicable instead
# of those above. If you wish to allow use of your version of this file only
# under the terms of either the GPL or the LGPL, and not to allow others to
# use your version of this file under the terms of the MPL, indicate your
# decision by deleting the provisions above and replace them with the notice
# and other provisions required by the GPL or the LGPL. If you do not delete
# the provisions above, a recipient may use your version of this file under
# the terms of any one of the MPL, the GPL or the LGPL.
#
# ***** END LICENSE BLOCK *****

package Bugzilla::Extension::BzAPI;
use strict;
use base qw(Bugzilla::Extension);

our $VERSION = '0.1';

# Add JSON filter for JSON templates
sub template_before_create {
    my ($self, $args) = @_;
    my $config = $args->{'config'};
    
    $config->{'FILTERS'}->{'json'} = sub {
        my ($var) = @_;
        $var =~ s/([\\\"\/])/\\$1/g;
        $var =~ s/\n/\\n/g;
        $var =~ s/\r/\\r/g;
        $var =~ s/\f/\\f/g;
        $var =~ s/\t/\\t/g;
        return $var;
    };
}

sub template_before_process {
    my ($self, $args) = @_;
    my $vars = $args->{'vars'};
    my $file = $args->{'file'};
    
    if ($file =~ /config\.json\.tmpl$/) {
        $vars->{'initial_status'} = Bugzilla::Status->can_change_to;
        $vars->{'status_objects'} = [Bugzilla::Status->get_all];        
    }
}

__PACKAGE__->NAME;
