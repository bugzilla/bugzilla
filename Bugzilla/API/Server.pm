# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::Server;

use 5.14.0;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Util qw(trick_taint trim disable_utf8);

use Digest::MD5 qw(md5_base64);
use File::Spec qw(catfile);
use HTTP::Request;
use HTTP::Response;
use JSON;
use Moo;
use Module::Runtime qw(require_module);
use Scalar::Util qw(blessed);
use Storable qw(freeze);

#############
# Constants #
#############

use constant DEFAULT_API_VERSION   => '1_0';
use constant DEFAULT_API_NAMESPACE => 'core';

#################################
# Set up basic accessor methods #
#################################

has api_ext         => (is => 'rw', default => 0);
has api_ext_version => (is => 'rw', default => '');
has api_options     => (is => 'rw', default => sub { [] });
has api_params      => (is => 'rw', default => sub { {} });
has api_path        => (is => 'rw', default => '');
has cgi             => (is => 'lazy');
has content_type    => (is => 'rw', default => 'application/json');
has controller      => (is => 'rw', default => undef);
has json            => (is => 'lazy');
has load_error      => (is => 'rw', default => undef);
has method_name     => (is => 'rw', default => '');
has request         => (is => 'lazy');
has success_code    => (is => 'rw', default => 200);

##################
# Public methods #
##################

sub server {
    my ($class) = @_;

    my $api_namespace = DEFAULT_API_NAMESPACE;
    my $api_version   = DEFAULT_API_VERSION;

    # First load the default server in case something fails
    # we still have something to return.
    my $server_class = "Bugzilla::API::${api_version}::Server";
    require_module($server_class);
    my $self = $server_class->new;

    my $path_info = Bugzilla->cgi->path_info;

    # If we do not match /<namespace>/<version>/ then we assume legacy calls
    # and use the default namespace and version.
    if ($path_info =~ m|^/([^/]+)/(\d+\.\d+(?:\.\d+)?)/|) {
        # First figure out the namespace we are accessing (core is native)
        $api_namespace = $1 if $path_info =~ s|^/([^/]+)||;
        $api_namespace = $self->_check_namespace($api_namespace);

        # Figure out which version we are looking for based on path
        $api_version = $1 if $path_info =~ s|^/(\d+\.\d+(?:\.\d+)?)(/.*)$|$2|;
        $api_version = $self->_check_version($api_version, $api_namespace);
    }

    # If the version pulled from the path is different than
    # what the server is currently, then reload as the new version.
    if ($api_version ne $self->api_version) {
        my $server_class = "Bugzilla::API::${api_version}::Server";
        require_module($server_class);
        $self = $server_class->new;
    }

    # Stuff away for later
    $self->api_path($path_info);

    return $self;
}

sub constants {
    my ($self) = @_;
    return $self->{_constants} if defined $self->{_constants};

    no strict 'refs';

    my $api_version = $self->api_version;
    my $class = "Bugzilla::API::${api_version}::Constants";
    require_module($class);

    $self->{_constants} = {};
    foreach my $constant (@{$class . "::EXPORT_OK"}) {
        if (ref $class->$constant) {
            $self->{_constants}->{$constant} = $class->$constant;
        }
        else {
            my @list = ($class->$constant);
            $self->{_constants}->{$constant} = (scalar(@list) == 1) ? $list[0] : \@list;
        }
    }

    return $self->{_constants};
}

sub response_header {
    my ($self, $code, $result) = @_;
    # The HTTP body needs to be bytes (not a utf8 string) for recent
    # versions of HTTP::Message, but JSON::RPC::Server doesn't handle this
    # properly. $_[1] is the HTTP body content we're going to be sending.
    if (utf8::is_utf8($result)) {
        utf8::encode($result);
        # Since we're going to just be sending raw bytes, we need to
        # set STDOUT to not expect utf8.
        disable_utf8();
    }
    my $h = HTTP::Headers->new;
    $h->header('Content-Type' => $self->content_type . '; charset=UTF-8');
    return HTTP::Response->new($code => undef, $h, $result);
}

###################################
# Public methods to be overridden #
###################################

sub handle { }
sub response { }
sub print_response { }
sub handle_login { }

###################
# Utility methods #
###################

sub return_error {
    my ($self, $status_code, $message, $error_code) = @_;
    if ($status_code && $message) {
        $self->{_return_error} = {
            status_code => $status_code,
            error       => JSON::true,
            message     => $message
        };
        $self->{_return_error}->{code} = $error_code if $error_code;
    }
    return $self->{_return_error};
}

sub callback {
    my ($self, $value) = @_;
    if (defined $value) {
        $value = trim($value);
        # We don't use \w because we don't want to allow Unicode here.
        if ($value !~ /^[A-Za-z0-9_\.\[\]]+$/) {
            ThrowUserError('json_rpc_invalid_callback', { callback => $value });
        }
        $self->{_callback} = $value;
        # JSONP needs to be parsed by a JS parser, not by a JSON parser.
        $self->content_type('text/javascript');
    }
    return $self->{_callback};
}

# ETag support
sub etag {
    my ($self, $data) = @_;
    my $cache = Bugzilla->request_cache;
    if (defined $data) {
        # Serialize the data if passed a reference
        local $Storable::canonical = 1;
        $data = freeze($data) if ref $data;

        # Wide characters cause md5_base64() to die.
        utf8::encode($data) if utf8::is_utf8($data);

        # Append content_type to the end of the data
        # string as we want the etag to be unique to
        # the content_type. We do not need this for
        # XMLRPC as text/xml is always returned.
        if (blessed($self) && $self->can('content_type')) {
            $data .= $self->content_type if $self->content_type;
        }

        $cache->{'_etag'} = md5_base64($data);
    }
    return $cache->{'_etag'};
}

# HACK: Allow error tag checking to work with t/012throwables.t
sub ThrowUserError {
    my ($error, $self, $vars) = @_;
    $self->load_error({ type  => 'user',
                        error => $error,
                        vars  => $vars });
}

sub ThrowCodeError {
    my ($error, $self, $vars) = @_;
    $self->load_error({ type  => 'code',
                        error => $error,
                        vars  => $vars });
}

###################
# Private methods #
###################

sub _build_cgi {
    return Bugzilla->cgi;
}

sub _build_json {
    # This may seem a little backwards to set utf8(0), but what this really
    # means is "don't convert our utf8 into byte strings, just leave it as a
    # utf8 string."
    return JSON->new->utf8(0)
           ->allow_blessed(1)
           ->convert_blessed(1);
}

sub _build_request {
    return HTTP::Request->new($_[0]->cgi->request_method, $_[0]->cgi->url);
}

sub _check_namespace {
    my ($self, $namespace) = @_;

    # No need to do anything else if native api
    return $namespace if lc($namespace) eq lc(DEFAULT_API_NAMESPACE);

    # Check if namespace matches an extension name
    my $found = 0;
    foreach my $extension (@{ Bugzilla->extensions }) {
        $found = 1 if lc($extension->NAME) eq lc($namespace);
    }
    # Make sure we have this namespace available
    if (!$found) {
        ThrowUserError('unknown_api_namespace', $self,
                       { api_namespace => $namespace });
        return DEFAULT_API_NAMESPACE;
    }

    return $namespace;
}

sub _check_version {
    my ($self, $version, $namespace) = @_;

    return DEFAULT_API_VERSION if !defined $version;

    my $old_version = $version;
    $version =~ s/\./_/g;

    my $version_dir;
    if (lc($namespace) eq 'core') {
        $version_dir = File::Spec->catdir('Bugzilla', 'API', $version);
    }
    else {
        $version_dir = File::Spec->catdir(bz_locations()->{extensionsdir},
                                          $namespace, 'API', $version);
    }

    # Make sure we actual have this version installed
    if (!-d $version_dir) {
        ThrowUserError('unknown_api_version', $self,
                       { api_version   => $old_version,
                         api_namespace => $namespace });
        return DEFAULT_API_VERSION;
    }

    # If we using an extension API, we need to determing which version of
    # the Core API it was written for.
    if (lc($namespace) ne 'core') {
        my $core_api_version;
        foreach my $extension (@{ Bugzilla->extensions }) {
            next if lc($extension->NAME) ne lc($namespace);
            if ($extension->API_VERSION_MAP
                && $extension->API_VERSION_MAP->{$version})
            {
                $self->api_ext_version($version);
                $version = $extension->API_VERSION_MAP->{$version};
            }
        }
    }

    return $version;
}

sub _best_content_type {
    my ($self, @types) = @_;
    my @accept_types = $self->_get_content_prefs();
    # Return the types as-is if no accept header sent, since sorting will be a no-op.
    if (!@accept_types) {
        return $types[0];
    }
    my $score = sub { $self->_score_type(shift, @accept_types) };
    my @scored_types = sort {$score->($b) <=> $score->($a)} @types;
    return $scored_types[0] || '*/*';
}

sub _score_type {
    my ($self, $type, @accept_types) = @_;
    my $score = scalar(@accept_types);
    for my $accept_type (@accept_types) {
        return $score if $type eq $accept_type;
        $score--;
    }
    return 0;
}

sub _get_content_prefs {
    my $self = shift;
    my $default_weight = 1;
    my @prefs;

    # Parse the Accept header, and save type name, score, and position.
    my @accept_types = split /,/, $self->cgi->http('accept') || '';
    my $order = 0;
    for my $accept_type (@accept_types) {
        my ($weight) = ($accept_type =~ /q=(\d\.\d+|\d+)/);
        my ($name) = ($accept_type =~ m#(\S+/[^;]+)#);
        next unless $name;
        push @prefs, { name => $name, order => $order++};
        if (defined $weight) {
            $prefs[-1]->{score} = $weight;
        } else {
            $prefs[-1]->{score} = $default_weight;
            $default_weight -= 0.001;
        }
    }

    # Sort the types by score, subscore by order, and pull out just the name
    @prefs = map {$_->{name}} sort {$b->{score} <=> $a->{score} ||
                                    $a->{order} <=> $b->{order}} @prefs;
    return @prefs;
}

####################################
# Private methods to be overridden #
####################################

sub _handle { }
sub _params_check { }
sub _retrieve_json_params { }
sub _find_resource { }

1;

__END__

=head1 NAME

Bugzilla::API::Server - The Web Service API interface to Bugzilla

=head1 DESCRIPTION

This is the standard API for external programs that want to interact
with Bugzilla. It provides various resources in various modules.

You interact with this API using L<REST|Bugzilla::API::Server>.

Full client documentation for the Bugzilla API can be found at
L<https://bugzilla.readthedocs.org/en/latest/api/index.html>.

=head1 USAGE

Methodl are grouped into "namespaces", like C<core> for
native Bugzilla API methods. Extensions reside in their own
I<namespaces> such as C<Example>. So, for example:

GET /example/1.0/bug1

calls

GET /bug/1

in the C<Example> namespace.

The endpoint for the API interface is the C<rest.cgi> script in
your Bugzilla installation. For example, if your Bugzilla is at
C<bugzilla.yourdomain.com>, to access the API and load a bug,
you would use C<http://bugzilla.yourdomain.com/rest.cgi/core/1.0/bug/35>.

If using Apache and mod_rewrite is installed and enabled, you can
simplify the endpoint by changing /rest.cgi/ to something like /api/
or something similar. So the same example from above would be:
C<http://bugzilla.yourdomain.com/api/core/1.0/bug/35> which is simpler
to remember.

Add this to your .htaccess file:

  <IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteRule ^rest/(.*)$ rest.cgi/$1 [NE]
  </IfModule>

=head1 BROWSING

If the Accept: header of a request is set to text/html (as it is by an
ordinary web browser) then the API will return the JSON data as a HTML
page which the browser can display. In other words, you can play with the
API using just your browser and see results in a human-readable form.
This is a good way to try out the various GET calls, even if you can't use
it for POST or PUT.

=head1 DATA FORMAT

The API only supports JSON input, and either JSON and JSONP output.
So objects sent and received must be in JSON format.

On every request, you must set both the "Accept" and "Content-Type" HTTP
headers to the MIME type of the data format you are using to communicate with
the API. Content-Type tells the API how to interpret your request, and Accept
tells it how you want your data back. "Content-Type" must be "application/json".
"Accept" can be either that, or "application/javascript" for JSONP - add a "callback"
parameter to name your callback.

Parameters may also be passed in as part of the query string for non-GET requests
and will override any matching parameters in the request body.

=head1 AUTHENTICATION

Along with viewing data as an anonymous user, you may also see private information
if you have a Bugzilla account by providing your login credentials.

=over

=item Login name and password

Pass in as query parameters of any request:

login=fred@example.com&password=ilovecheese

Remember to URL encode any special characters, which are often seen in passwords and to
also enable SSL support.

=item Login token

By calling GET /login?login=fred@example.com&password=ilovecheese, you get back
a C<token> value which can then be passed to each subsequent call as
authentication. This is useful for third party clients that cannot use cookies
and do not want to store a user's login and password in the client. You can also
pass in "token" as a convenience.

=item API Key

You can also authenticate by passing an C<api_key> value as part of the query
parameters which is setup using the I<API Keys> tab in C<userprefs.cgi>.

=back

=head1 ERRORS

When an API error occurs, a data structure is returned with the key C<error>
set to C<true>.

The error contents look similar to:

 { "error": true, "message": "Some message here", "code": 123 }

=head1 CONSTANTS

=over

=item DEFAULT_API_VERSION

The default API version that is used by C<server>.
Current default is L<1.0> which is the first version of the API implemented in this way..

=item DEFAULT_API_NAMESPACE

The default API namespace that is used if C<server> is called before C<init_serber>.
Current default is L<core> which is the native API methods (non-extension).

=back

=head1 METHODS

The L<Bugzilla::API::Server> has the following methods used by various
code in Bugzilla.

=over

=item server

Returns a L<Bugzilla::API::Server> object after looking at the cgi path to
determine which version of the API is being requested and which namespace to
load methods from. A new server instance of the proper version is returned.

=item constants

A method return a hash containing the constants from the Constants.pm module
in the API version directory. The calling code will not need to know which
version of the API is being used to access the constant values.

=item json

Returns a L<JSON> encode/decoder object.

=item load_error

Method that stores error data if a API module fails to load and ThrowUserError
or ThrowCodeError needs to send a proper error to the client.

=item cgi

Returns a L<Bugzilla::CGI> object.

=item request

Returns a L<HTTP::Request> object.

=item response_header

Returns a L<HTTP::Response> object with the appropriate content-type set.
Requires that a status code and content data to be passed in.

=item handle

Handles the current request by finding the correct resource, setting the parameters,
authentication, executing the resource, and forming an appropriate response.

=item response

Encodes the return data in the requested content-type and also does some other
changes such as conversion to JSONP and setting status_code. Also sets the eTag
header values based on the result content.

=item print_response

Prints the final response headers and content to STDOUT.

=item handle_login

Authenticates the user and performs additional checks.

=item return_error

If an error occurs, this method will return a data structure describing the error
with a code and message.

=item callback

When calling the API over GET, you can use the "JSONP" method of doing cross-domain
requests, if you want to access the API directly on a web page from another site.
JSONP is described at L<http://bob.pythonmac.org/archives/2005/12/05/remote-json-jsonp/>.

To use JSONP with Bugzilla's API, simply specify a C<callback> parameter when
using it via GET as described above. For example, here's some HTML you could use
to get the time on a remote Bugzilla website, using JSONP:

 <script type="text/javascript" src="http://bugzilla.example.com/time?callback=foo">

That would call the API path for C<time> and pass its value to a function
called C<foo> as the only argument. All the other URL parameters (such as for
passing in arguments to methods) that can be passed during GET requests are also
available, of course. The above is just the simplest possible example.

The values returned when using JSONP are identical to the values returned
when not using JSONP, so you will also get error messages if there is an
error.

The C<callback> URL parameter may only contain letters, numbers, periods, and
the underscore (C<_>) character. Including any other characters will cause
Bugzilla to throw an error. (This error will be a normal API response, not JSONP.)

=item etag

Using the data structure passed to the subroutine, we convert the data to a string
and then md5 hash the string to creates a value for the eTag header. This allows
a user to include the value in seubsequent requests and only return the full data
if it has changed.

=item api_ext

A boolean value signifying if the current request is for an API method is exported
by an extension or is part of the core methods.

=item api_ext_version

If the current request is for an extension API method, this is the version of the
extension API that should be used.

=item api_namespace

The current namespace of the API method being requested as determined by the
cgi path. If a namespace is not provided, we default to L<core>.

=item api_options

Once a resource has been matched to the current request, this the available options
to the client such as GET, PUT, etc.

=item api_params

Once a resource has been matched, this is the params that were pulled from the
regex used to match the resource. This could be a resource id or name such as
a bug id, etc.

=item api_path

The final cgi path after namespace and version have been removed. This is the
path used to locate a matching resource from the controller modules.

=item api_version

The current version of the L<core> API that is being used for processing the
request. Note that this version may be different from C<api_ext_version> if
the client requested a method in an extension's namespace.

=item content_type

The content-type of the data that will be returned. The current default is
L<application/json>. If a caller is msking a request using a browser, it will
most likely be L<text/html>.

=item controller

Once a resource has been matched, this is the controller module that contains
the method that will be executed.

=item method_name

The method in the controller module that will be executed to handle the request.

=item success_code

The success code to be used when creating the L<response> object to be returned.
It can be different depending on if the request was successful, a resource was
created, or an error occurred.

=back

=head1 B<Methods in need of POD>

=over

=item ThrowCodeError

=item ThrowUserError

=back

