# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BzAPI;

use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Extension::BzAPI::Constants;
use Bugzilla::Extension::BzAPI::Util qw(fix_credentials filter_wants_nocache);

use Bugzilla::Error;
use Bugzilla::Util qw(trick_taint datetime_from);
use Bugzilla::Constants;
use Bugzilla::Install::Filesystem;

use File::Basename;

our $VERSION = '0.1';

################
# Installation #
################

sub install_filesystem {
    my ($self,  $args) = @_;
    my $files = $args->{'files'};

    my $extensionsdir = bz_locations()->{'extensionsdir'};
    my $scriptname = $extensionsdir . "/" . __PACKAGE__->NAME . "/bin/rest.cgi";

    $files->{$scriptname} = {
        perms => Bugzilla::Install::Filesystem::WS_EXECUTE
    };
}

##################
# Template Hooks #
##################

sub template_before_process {
    my ($self, $args) = @_;
    my $vars = $args->{'vars'};
    my $file = $args->{'file'};

    if ($file =~ /config\.json\.tmpl$/) {
        $vars->{'initial_status'} = Bugzilla::Status->can_change_to;
        $vars->{'status_objects'} = [ Bugzilla::Status->get_all ];
    }
}

##############
# Code Hooks #
##############

sub bug_start_of_update {
    my ($self, $args) = @_;
    my $old_bug = $args->{old_bug};
    my $params = Bugzilla->input_params;

    return if !Bugzilla->request_cache->{bzapi};

    # Check for a mid-air collision. Currently this only works when updating
    # an individual bug and if last_changed_time is provided. Otherwise it
    # allows the changes.
    my $delta_ts = $params->{last_change_time} || '';

    if ($delta_ts && exists $params->{ids} && @{ $params->{ids} } == 1) {
        _midair_check($delta_ts, $old_bug->delta_ts);
    }
}

sub object_end_of_set_all {
    my ($self, $args) = @_;
    my $object = $args->{object};
    my $params = Bugzilla->input_params;

    return if !Bugzilla->request_cache->{bzapi};
    return if !$object->isa('Bugzilla::Attachment');

    # Check for a mid-air collision. Currently this only works when updating
    # an individual attachment and if last_changed_time is provided. Otherwise it
    # allows the changes.
    my $stash = Bugzilla->request_cache->{bzapi_stash} ||= {};
    my $delta_ts = $stash->{last_change_time};

    _midair_check($delta_ts, $object->modification_time) if $delta_ts;
}

sub _midair_check {
    my ($delta_ts, $old_delta_ts) = @_;
    my $delta_ts_z = datetime_from($delta_ts)
        || ThrowCodeError('invalid_timestamp', { timestamp => $delta_ts });
    my $old_delta_tz_z = datetime_from($old_delta_ts);
    if ($old_delta_tz_z ne $delta_ts_z) {
        ThrowUserError('bzapi_midair_collision');
    }
}

sub webservice_error_codes {
    my ($self, $args) = @_;
    my $error_map = $args->{error_map};
    $error_map->{'bzapi_midair_collision'} = 400;
}

sub webservice_fix_credentials {
    my ($self, $args) = @_;
    my $rpc    = $args->{rpc};
    my $params = $args->{params};
    fix_credentials($params);
}

sub webservice_rest_request {
    my ($self, $args) = @_;
    my $rpc    = $args->{rpc};
    my $params = $args->{params};
    my $cache  = Bugzilla->request_cache;

    return if !$cache->{bzapi};

    # Stash certain values for later use
    $cache->{bzapi_rpc} = $rpc;

    # Internal websevice method being used
    $cache->{bzapi_rpc_method} = $rpc->path_info . "." . $rpc->bz_method_name;

    # Load the appropriate request handler based on path and type
    if (my $handler = _find_handler($rpc, 'request')) {
        &$handler($params);
    }
}

sub webservice_rest_response {
    my ($self, $args) = @_;
    my $rpc      = $args->{rpc};
    my $result   = $args->{result};
    my $response = $args->{response};
    my $cache    = Bugzilla->request_cache;

    # Stash certain values for later use
    $cache->{bzapi_rpc} ||= $rpc;

    return if !Bugzilla->request_cache->{bzapi}
              || ref $$result ne 'HASH'
              || exists $$result->{error};

    # Load the appropriate response handler based on path and type
    if (my $handler = _find_handler($rpc, 'response')) {
        &$handler($result, $response);
    }
}

sub webservice_rest_resources {
    my ($self, $args) = @_;
    my $rpc       = $args->{rpc};
    my $resources = $args->{resources};

    return if !Bugzilla->request_cache->{bzapi};

    _add_resources($rpc, $resources);
}

#####################
# Utility Functions #
#####################

sub _find_handler {
    my ($rpc, $type) = @_;

    my $path_info      = $rpc->cgi->path_info;
    my $request_method = $rpc->request->method;

    my $module = $rpc->bz_class_name || '';
    $module =~ s/^Bugzilla::WebService:://;

    my $cache = _preload_handlers();

    return undef if !exists $cache->{$module};

    # Make a copy of the handler array so
    # as to not alter the actual cached data.
    my @handlers = @{ $cache->{$module} };

    while (my $regex = shift @handlers) {
        my $data = shift @handlers;
        next if ref $data ne 'HASH';
        if ($path_info =~ $regex
            && exists $data->{$request_method}
            && exists $data->{$request_method}->{$type})
        {
            return $data->{$request_method}->{$type};
        }
    }

    return undef;
}

sub _add_resources {
    my ($rpc, $native_resources) = @_;

    my $cache = _preload_handlers();

    foreach my $module (keys %$cache) {
        my $native_module = "Bugzilla::WebService::$module";
        next if !$native_resources->{$native_module};

        # Make a copy of the handler array so
        # as to not alter the actual cached data.
        my @handlers = @{ $cache->{$module} };

        my @ext_resources = ();
        while (my $regex = shift @handlers) {
            my $data = shift @handlers;
            next if ref $data ne 'HASH';
            my $new_data = {};
            foreach my $request_method (keys %$data) {
                next if !exists $data->{$request_method}->{resource};
                $new_data->{$request_method} = $data->{$request_method}->{resource};
            }
            push(@ext_resources, $regex, $new_data);
        }

        # Places the new resources at the beginning of the list
        # so we can capture specific paths before the native resources
        unshift(@{$native_resources->{$native_module}}, @ext_resources);
    }
}

sub _resource_modules {
    my $extdir = bz_locations()->{extensionsdir};
    return map { basename($_, '.pm') } glob("$extdir/" . __PACKAGE__->NAME . "/lib/Resources/*.pm");
}

# preload all handlers into cache
# since we don't want to parse all
# this multiple times
sub _preload_handlers {
    my $cache = Bugzilla->request_cache;

    if (!exists $cache->{rest_handlers}) {
        my $all_handlers = {};
        foreach my $module (_resource_modules()) {
            my $resource_class = "Bugzilla::Extension::BzAPI::Resources::$module";
            trick_taint($resource_class);
            eval("require $resource_class");
            warn $@ if $@;
            next if ($@ || !$resource_class->can('rest_handlers'));
            my $handlers = $resource_class->rest_handlers;
            next if (ref $handlers ne 'ARRAY' || scalar @$handlers % 2 != 0);
            $all_handlers->{$module} = $handlers;
        }
        $cache->{rest_handlers} = $all_handlers;
    }

    return $cache->{rest_handlers};
}

__PACKAGE__->NAME;
