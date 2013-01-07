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
# The Original Code is the BrowserID Bugzilla Extension.
#
# The Initial Developer of the Original Code is the Mozilla Foundation.
# Portions created by the Initial Developer are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Gervase Markham <gerv@gerv.net>

package Bugzilla::Extension::BrowserID;
use strict;
use base qw(Bugzilla::Extension);

our $VERSION = '0.01';

sub auth_login_methods {
    my ($self, $args) = @_;
    my $modules = $args->{'modules'};
    if (exists($modules->{'BrowserID'})) {
        $modules->{'BrowserID'} = 'Bugzilla/Extension/BrowserID/Login.pm';
    }
}

sub config_modify_panels {
    my ($self, $args) = @_;
    my $panels = $args->{'panels'};
    my $auth_panel_params = $panels->{'auth'}->{'params'};
    
    my ($user_info_class) = 
                grep { $_->{'name'} eq 'user_info_class' } @$auth_panel_params;

    if ($user_info_class) {
        push(@{ $user_info_class->{'choices'} }, "BrowserID,CGI");
    }
}

sub config_add_panels {
    my ($self, $args) = @_;
    my $modules = $args->{panel_modules};
    $modules->{BrowserID} = "Bugzilla::Extension::BrowserID::Config";
}

__PACKAGE__->NAME;
