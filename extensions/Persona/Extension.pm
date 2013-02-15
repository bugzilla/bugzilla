# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Persona;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Config qw(SetParam write_params);

our $VERSION = '0.01';

sub install_update_db {
    # The extension changed from BrowserID to Persona
    # so we need to update user_info_class if this system
    # was using BrowserID for verification.
    my $params  = Bugzilla->params || Bugzilla::Config::read_param_file();
    my $user_info_class = $params->{'user_info_class'};
    if ($user_info_class =~ /BrowserID/) {
        $user_info_class =~ s/BrowserID/Persona/;
        SetParam('user_info_class', $user_info_class);
        write_params();
    }
}

sub auth_login_methods {
    my ($self, $args) = @_;
    my $modules = $args->{'modules'};
    if (exists($modules->{'Persona'})) {
        $modules->{'Persona'} = 'Bugzilla/Extension/Persona/Login.pm';
    }
}

sub config_modify_panels {
    my ($self, $args) = @_;
    my $panels = $args->{'panels'};
    my $auth_panel_params = $panels->{'auth'}->{'params'};
    
    my ($user_info_class) = 
                grep { $_->{'name'} eq 'user_info_class' } @$auth_panel_params;

    if ($user_info_class) {
        push(@{ $user_info_class->{'choices'} }, "Persona,CGI");
    }

    # The extension changed from BrowserID to Persona
    # so we need to retain the current values for the new
    # params that will be created.
    my $params  = Bugzilla->params || Bugzilla::Config::read_param_file();
    my $verify_url = $params->{'browserid_verify_url'};
    my $includejs_url = $params->{'browserid_includejs_url'};
    if ($verify_url && $includejs_url) {
        foreach my $param (@{ $panels->{'persona'}->{'params'} }) {
            if ($param->{'name'} eq 'persona_verify_url') {
                $param->{'default'} = $verify_url;
            }
            if ($param->{'name'} eq 'persona_includejs_url') {
                $param->{'default'} = $includejs_url;
            }
        }
    }
}

sub config_add_panels {
    my ($self, $args) = @_;
    my $modules = $args->{panel_modules};
    $modules->{Persona} = "Bugzilla::Extension::Persona::Config";
}

__PACKAGE__->NAME;
