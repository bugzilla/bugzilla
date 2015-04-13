# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::1_0::Server;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::API::1_0::Constants qw(API_AUTH_HEADERS);
use Bugzilla::API::1_0::Util qw(taint_data fix_credentials api_include_exclude);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Hook;
use Bugzilla::Util qw(datetime_from trick_taint);

use File::Basename qw(basename);
use File::Glob qw(bsd_glob);
use List::MoreUtils qw(none uniq);
use MIME::Base64 qw(decode_base64 encode_base64);
use Moo;
use Scalar::Util qw(blessed);

extends 'Bugzilla::API::Server';

############
# Start up #
############

has api_version   => (is => 'ro', default => '1_0',  init_arg => undef);
has api_namespace => (is => 'ro', default => 'core', init_arg => undef);

sub _build_content_type {
    # Determine how the data should be represented. We do this early so
    # errors will also be returned with the proper content type.
    # If no accept header was sent or the content types specified were not
    # matched, we default to the first type in the whitelist.
    return $_[0]->_best_content_type(
        @{ $_[0]->constants->{REST_CONTENT_TYPE_WHITELIST} });
}

##################
# Public Methods #
##################

sub handle {
    my ($self)  = @_;

   # Using current path information, decide which class/method to
    # use to serve the request. Throw error if no resource was found
    # unless we were looking for OPTIONS
    if (!$self->_find_resource) {
        if ($self->request->method eq 'OPTIONS'
            && $self->api_options)
        {
            my $response = $self->response_header($self->constants->{STATUS_OK}, "");
            my $options_string = join(', ', @{ $self->api_options });
            $response->header('Allow' => $options_string,
                              'Access-Control-Allow-Methods' => $options_string);
            return $self->print_response($response);
        }

        ThrowUserError("rest_invalid_resource",
                       { path   => $self->cgi->path_info,
                         method => $self->request->method });
    }

    my $params = $self->_retrieve_json_params;
    $self->_params_check($params);

    fix_credentials($params);

    # Fix includes/excludes for each call
    api_include_exclude($params);

    # Set callback name if exists
    $self->callback($params->{'callback'}) if $params->{'callback'};

    Bugzilla->input_params($params);

    # Let's try to authenticate before executing
    $self->handle_login;

    # Execute the handler
    my $result = $self->_handle;

    # The result needs to be a valid JSON data structure
    # and not a undefined or scalar value.
    if (!ref $result
        || blessed($result)
        || ref $result ne 'HASH'
        || ref $result ne 'ARRAY')
    {
        $result = { result => $result };
    }

    $self->response($result);
}

sub response {
    my ($self, $result) = @_;

    # Error data needs to be formatted differently
    my $status_code;
    if (my $error = $self->return_error) {
        $status_code = delete $error->{status_code};
        $error->{documentation} = REST_DOC;
        $result = $error;
    }
    else {
        $status_code = $self->success_code;
    }

    Bugzilla::Hook::process('webservice_rest_result',
        { api => $self, result => \$result });

    # ETag support
    my $etag = $self->etag;
    $self->etag($result) if !$etag;

    # If accessing through web browser, then display in readable format
    my $content;
    if ($self->content_type eq 'text/html') {
        $result = $self->json->pretty->canonical->allow_nonref->encode($result);
        my $template = Bugzilla->template;
        $template->process("rest.html.tmpl", { result => $result }, \$content)
            || ThrowTemplateError($template->error());
    }
    else {
        $content = $self->json->encode($result);
    }

    if (my $callback = $self->callback) {
        # Prepend the response with /**/ in order to protect
        # against possible encoding attacks (e.g., affecting Flash).
        $content = "/**/$callback($content)";
    }

    my $response = $self->response_header($status_code, $content);

    Bugzilla::Hook::process('webservice_rest_response',
        { api => $self, response => $response });

    $self->print_response($response);
}

sub print_response {
    my ($self, $response) = @_;

    # Access Control
    my @allowed_headers = qw(accept content-type origin x-requested-with);
    foreach my $header (keys %{ API_AUTH_HEADERS() }) {
        # We want to lowercase and replace _ with -
        my $translated_header = $header;
        $translated_header =~ tr/A-Z_/a-z\-/;
        push(@allowed_headers, $translated_header);
    }
    $response->header("Access-Control-Allow-Origin", "*");
    $response->header("Access-Control-Allow-Headers", join(', ', @allowed_headers));

    # Use $cgi->header properly instead of just printing text directly.
    # This fixes various problems, including sending Bugzilla's cookies
    # properly.
    my $headers = $response->headers;
    my @header_args;
    foreach my $name ($headers->header_field_names) {
        my @values = $headers->header($name);
        $name =~ s/-/_/g;
        foreach my $value (@values) {
            push(@header_args, "-$name", $value);
        }
    }

    # ETag support
    my $etag = $self->etag;
    if ($etag && $self->cgi->check_etag($etag)) {
        push(@header_args, "-ETag", $etag);
        print $self->cgi->header(-status => '304 Not Modified', @header_args);
    }
    else {
        push(@header_args, "-ETag", $etag) if $etag;
        print $self->cgi->header(-status => $response->code, @header_args);
        print $response->content;
    }
}

sub handle_login {
    my $self = shift;
    my $controller = $self->controller;
    my $method     = $self->method_name;

    return if ($controller->login_exempt($method)
               and !defined Bugzilla->input_params->{Bugzilla_login});

    Bugzilla->login();

    Bugzilla::Hook::process('webservice_before_call',
                            { rpc => $self, controller => $controller });
}

###################
# Private Methods #
###################

sub _handle {
    my ($self) = shift;
    my $method     = $self->method_name;
    my $controller = $self->controller;
    my $params     = Bugzilla->input_params;

    unless ($controller->can($method)) {
        return $self->return_error(302, "No such a method : '$method'.");
    }

    my $result = eval q| $controller->$method($params) |;

    if ($@) {
        return $self->return_error(500, "Procedure error: $@");
    }

    # Set the ETag if not already set in the webservice methods.
    my $etag = $self->etag;
    if (!$etag && ref $result) {
        $self->etag($result);
    }

    return $result;
}

sub _params_check {
    my ($self, $params) = @_;
    my $method     = $self->method_name;
    my $controller = $self->controller;

    taint_data($params);

    # Now, convert dateTime fields on input.
    my @date_fields = @{ $controller->DATE_FIELDS->{$method} || [] };
    foreach my $field (@date_fields) {
        if (defined $params->{$field}) {
            my $value = $params->{$field};
            if (ref $value eq 'ARRAY') {
                $params->{$field} =
                    [ map { $self->datetime_format_inbound($_) } @$value ];
            }
            else {
                $params->{$field} = $self->datetime_format_inbound($value);
            }
        }
    }
    my @base64_fields = @{ $controller->BASE64_FIELDS->{$method} || [] };
    foreach my $field (@base64_fields) {
        if (defined $params->{$field}) {
            $params->{$field} = decode_base64($params->{$field});
        }
    }

    if ($self->request->method eq 'POST'
        || $self->request->method eq 'PUT') {
        # CSRF is possible via XMLHttpRequest when the Content-Type header
        # is not application/json (for example: text/plain or
        # application/x-www-form-urlencoded).
        # application/json is the single official MIME type, per RFC 4627.
        my $content_type = $self->cgi->content_type;
        # The charset can be appended to the content type, so we use a regexp.
        if ($content_type !~ m{^application/json(-rpc)?(;.*)?$}i) {
            ThrowUserError('json_rpc_illegal_content_type',
                            { content_type => $content_type });
        }
    }
    else {
        # When being called using GET, we don't allow calling
        # methods that can change data. This protects us against cross-site
        # request forgeries.
        if (!grep($_ eq $method, $controller->READ_ONLY)) {
            ThrowUserError('json_rpc_post_only',
                           { method => $self->method_name });
        }
    }

    # Only allowed methods to be used from our whitelist
    if (none { $_ eq $method} $controller->PUBLIC_METHODS) {
        ThrowCodeError('unknown_method', { method => $self->method_name });
    }
}

sub _retrieve_json_params {
    my $self = shift;

    # Make a copy of the current input_params rather than edit directly
    my $params = {};
    %{$params} = %{ Bugzilla->input_params };

    # First add any parameters we were able to pull out of the path
    # based on the resource regexp and combine with the normal URL
    # parameters.
    if (my $api_params = $self->api_params) {
        foreach my $param (keys %$api_params) {
            # If the param does not already exist or if the
            # rest param is a single value, add it to the
            # global params.
            if (!exists $params->{$param} || !ref $api_params->{$param}) {
                $params->{$param} = $api_params->{$param};
            }
            # If param is a list then add any extra values to the list
            elsif (ref $api_params->{$param}) {
                my @extra_values = ref $params->{$param}
                                   ? @{ $params->{$param} }
                                   : ($params->{$param});
                $params->{$param}
                    = [ uniq (@{ $api_params->{$param} }, @extra_values) ];
            }
        }
    }

    # Any parameters passed in in the body of a non-GET request will override
    # any parameters pull from the url path. Otherwise non-unique keys are
    # combined.
    if ($self->request->method ne 'GET') {
        my $extra_params = {};
        # We do this manually because CGI.pm doesn't understand JSON strings.
        my $json = delete $params->{'POSTDATA'} || delete $params->{'PUTDATA'};
        if ($json) {
            eval { $extra_params = $self->json->decode($json); };
            if ($@) {
                ThrowUserError('json_rpc_invalid_params', { err_msg  => $@ });
            }
        }

        # Allow parameters in the query string if request was non-GET.
        # Note: parameters in query string body override any matching
        # parameters in the request body.
        foreach my $param ($self->cgi->url_param()) {
            $extra_params->{$param} = $self->cgi->url_param($param);
        }

        %{$params} = (%{$params}, %{$extra_params}) if %{$extra_params};
    }

    return $params;
}

sub _find_resource {
    my ($self) = @_;
    my $api_version     = $self->api_version;
    my $api_ext_version = $self->api_ext_version;
    my $api_namespace   = $self->api_namespace;
    my $api_path        = $self->api_path;
    my $request_method  = $self->request->method;
    my $resource_found  = 0;

    my $resource_modules;
    if ($api_ext_version) {
        $resource_modules = File::Spec->catdir(bz_locations()->{extensionsdir},
            $api_namespace, 'API', $api_ext_version, 'Resource', '*.pm');
    }
    else {
        $resource_modules = File::Spec->catdir('Bugzilla','API', $api_version,
            'Resource', '*.pm');
    }

    # Load in the WebService modules from the appropriate version directory
    # and then call $module->REST_RESOURCES to get the resources array ref.
    foreach my $module_file (bsd_glob($resource_modules)) {
        # Create a controller object
        trick_taint($module_file);
        my $module_basename = basename($module_file, '.pm');
        eval { require "$module_file"; } || die $@;
        my $module_class = "Bugzilla::API::${api_version}::Resource::${module_basename}";
        my $controller = $module_class->new;
        next if !$controller || !$controller->can('REST_RESOURCES');

        # The resource data for each module needs to be an array ref with an
        # even number of elements to work correctly.
        my $this_resources = $controller->REST_RESOURCES;
        next if (ref $this_resources ne 'ARRAY' || scalar @$this_resources % 2 != 0);

        while (my ($regex, $options_data) = splice(@$this_resources, 0, 2)) {
            next if ref $options_data ne 'HASH';

            if (my @matches = ($self->api_path =~ $regex)) {
                # If a specific path is accompanied by a OPTIONS request
                # method, the user is asking for a list of possible request
                # methods for a specific path.
                $self->api_options([ keys %$options_data ]);

                if ($options_data->{$request_method}) {
                    my $resource_data = $options_data->{$request_method};

                    # The method key/value can be a simple scalar method name
                    # or a anonymous subroutine so we execute it here.
                    my $method = ref $resource_data->{method} eq 'CODE'
                                 ? $resource_data->{method}->($self)
                                 : $resource_data->{method};
                    $self->method_name($method);

                    # Pull out any parameters parsed from the URL path
                    # and store them for use by the method.
                    if ($resource_data->{params}) {
                        $self->api_params($resource_data->{params}->(@matches));
                    }

                    # If a special success code is needed for this particular
                    # method, then store it for later when generating response.
                    if ($resource_data->{success_code}) {
                        $self->success_code($resource_data->{success_code});
                    }

                    # Stash away for later
                    $self->controller($controller);

                    # No need to look further
                    $resource_found = 1;
                    last;
                }
            }
        }
        last if $resource_found;
    }

    return $resource_found;
}

1;

__END__

=head1 NAME

Bugzilla::API::1_0::Server - The API 1.0 Interface to Bugzilla

=head1 DESCRIPTION

This documentation describes version 1.0 of the Bugzilla API. This
module inherits from L<Bugzilla::API::Server> and overrides specific
methods to make this version distinct from other versions of the API.
New versions of the API may make breaking changes by implementing
these methods in a different way.

=head1 SEE ALSO

L<Bugzilla::API::Server>

=head1 B<Methods in need of POD>

=over

=item handle

=item response

=item print_response

=item handle_login

=back

