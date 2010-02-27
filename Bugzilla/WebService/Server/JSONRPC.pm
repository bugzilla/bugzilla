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
# The Original Code is the Bugzilla JSON Webservices Interface.
#
# The Initial Developer of the Original Code is the San Jose State
# University Foundation. Portions created by the Initial Developer
# are Copyright (C) 2008 the Initial Developer. All Rights Reserved.
#
# Contributor(s): 
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::WebService::Server::JSONRPC;

use strict;
use base qw(JSON::RPC::Server::CGI Bugzilla::WebService::Server);

use Bugzilla::Error;
use Bugzilla::WebService::Constants;
use Bugzilla::WebService::Util qw(taint_data);
use Bugzilla::Util qw(datetime_from);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    Bugzilla->_json_server($self);
    $self->dispatch(WS_DISPATCH);
    $self->return_die_message(1);
    return $self;
}

sub create_json_coder {
    my $self = shift;
    my $json = $self->SUPER::create_json_coder(@_);
    $json->allow_blessed(1);
    $json->convert_blessed(1);
    # This may seem a little backwards, but what this really means is
    # "don't convert our utf8 into byte strings, just leave it as a
    # utf8 string."
    $json->utf8(0) if Bugzilla->params->{'utf8'};
    return $json;
}

# Override the JSON::RPC method to return our CGI object instead of theirs.
sub cgi { return Bugzilla->cgi; }

sub type {
    my ($self, $type, $value) = @_;
    
    # This is the only type that does something special with undef.
    if ($type eq 'boolean') {
        return $value ? JSON::true : JSON::false;
    }
    
    return JSON::null if !defined $value;

    my $retval = $value;

    if ($type eq 'int') {
        $retval = int($value);
    }
    if ($type eq 'double') {
        $retval = 0.0 + $value;
    }
    elsif ($type eq 'string') {
        # Forces string context, so that JSON will make it a string.
        $retval = "$value";
    }
    elsif ($type eq 'dateTime') {
        # ISO-8601 "YYYYMMDDTHH:MM:SS" with a literal T
        $retval = $self->datetime_format($value);
    }
    # XXX Will have to implement base64 if Bugzilla starts using it.

    return $retval;
}

sub datetime_format {
    my ($self, $date_string) = @_;

    # YUI expects ISO8601 in UTC time; uncluding TZ specifier
    my $time = datetime_from($date_string, 'UTC');
    my $iso_datetime = $time->iso8601() . 'Z';
    return $iso_datetime;
}


# Store the ID of the current call, because Bugzilla::Error will need it.
sub _handle {
    my $self = shift;
    my ($obj) = @_;
    $self->{_bz_request_id} = $obj->{id};
    return $self->SUPER::_handle(@_);
}

# Make all error messages returned by JSON::RPC go into the 100000
# range, and bring down all our errors into the normal range.
sub _error {
    my ($self, $id, $code) = (shift, shift, shift);
    # All JSON::RPC errors are less than 1000.
    if ($code < 1000) {
        $code += 100000;
    }
    # Bugzilla::Error adds 100,000 to all *our* errors, so
    # we know they came from us.
    elsif ($code > 100000) {
        $code -= 100000;
    }

    # We can't just set $_[1] because it's not always settable,
    # in JSON::RPC::Server.
    unshift(@_, $id, $code);
    my $json = $self->SUPER::_error(@_);

    # We want to always send the JSON-RPC 1.1 error format, although
    # If we're not in JSON-RPC 1.1, we don't need the silly "name" parameter.
    if (!$self->version or $self->version ne '1.1') {
        my $object = $self->json->decode($json);
        my $message = $object->{error};
        # Just assure that future versions of JSON::RPC don't change the
        # JSON-RPC 1.0 error format.
        if (!ref $message) {
            $object->{error} = {
                code    => $code,
                message => $message,
            };
            $json = $self->json->encode($object);
        }
    }
    return $json;
}

##################
# Login Handling #
##################

# This handles dispatching our calls to the appropriate class based on
# the name of the method.
sub _find_procedure {
    my $self = shift;

    # This is also a good place to deny GET requests, since we can
    # safely call ThrowUserError at this point.
    if ($self->request->method ne 'POST') {
        ThrowUserError('json_rpc_post_only');
    }

    my $method = shift;
    $self->{_bz_method_name} = $method;

    # This tricks SUPER::_find_procedure into finding the right class.
    $method =~ /^(\S+)\.(\S+)$/;
    $self->path_info($1);
    unshift(@_, $2);

    return $self->SUPER::_find_procedure(@_);
}

# This is a hacky way to do something right before methods are called.
# This is the last thing that JSON::RPC::Server::_handle calls right before
# the method is actually called.
sub _argument_type_check {
    my $self = shift;
    my $params = $self->SUPER::_argument_type_check(@_);

    # JSON-RPC 1.0 requires all parameters to be passed as an array, so
    # we just pull out the first item and assume it's an object.
    my $params_is_array;
    if (ref $params eq 'ARRAY') {
        $params = $params->[0];
        $params_is_array = 1;
    }

    taint_data($params);

    # Now, convert dateTime fields on input.
    $self->_bz_method_name =~ /^(\S+)\.(\S+)$/;
    my ($class, $method) = ($1, $2);
    my $pkg = $self->{dispatch_path}->{$class};
    my @date_fields = @{ $pkg->DATE_FIELDS->{$method} || [] };
    foreach my $field (@date_fields) {
        if (defined $params->{$field}) {
            my $value = $params->{$field};
            if (ref $value eq 'ARRAY') {
                $params->{$field} = 
                    [ map { $self->_bz_convert_datetime($_) } @$value ];
            }
            else {
                $params->{$field} = $self->_bz_convert_datetime($value);
            }
        }
    }

    Bugzilla->input_params($params);

    # This is the best time to do login checks.
    $self->handle_login();

    # Bugzilla::WebService packages call internal methods like
    # $self->_some_private_method. So we have to inherit from 
    # that class as well as this Server class.
    my $new_class = ref($self) . '::' . $pkg;
    my $isa_string = 'our @ISA = qw(' . ref($self) . " $pkg)";
    eval "package $new_class;$isa_string;";
    bless $self, $new_class;

    if ($params_is_array) {
        $params = [$params];
    }

    return $params;
}

sub _bz_convert_datetime {
    my ($self, $time) = @_;
    
    my $converted = datetime_from($time, Bugzilla->local_timezone);
    $time = $converted->ymd() . ' ' . $converted->hms();
    return $time
}

sub handle_login {
    my $self = shift;

    my $path = $self->path_info;
    my $class = $self->{dispatch_path}->{$path};
    my $full_method = $self->_bz_method_name;
    $full_method =~ /^\S+\.(\S+)/;
    my $method = $1;
    $self->SUPER::handle_login($class, $method, $full_method);
}

# _bz_method_name is stored by _find_procedure for later use.
sub _bz_method_name {
    return $_[0]->{_bz_method_name}; 
}

1;

__END__

=head1 NAME

Bugzilla::WebService::Server::JSONRPC - The JSON-RPC Interface to Bugzilla

=head1 DESCRIPTION

This documentation describes things about the Bugzilla WebService that
are specific to JSON-RPC. For a general overview of the Bugzilla WebServices,
see L<Bugzilla::WebService>.

Please note that I<everything> about this JSON-RPC interface is
B<EXPERIMENTAL>. If you want a fully stable API, please use the
C<Bugzilla::WebService::Server::XMLRPC|XML-RPC> interface.

=head1 JSON-RPC

Bugzilla supports both JSON-RPC 1.0 and 1.1. We recommend that you use
JSON-RPC 1.0 instead of 1.1, though, because 1.1 is deprecated.

At some point in the future, Bugzilla may also support JSON-RPC 2.0.

The JSON-RPC standards are described at L<http://json-rpc.org/>.

=head1 CONNECTING

The endpoint for the JSON-RPC interface is the C<jsonrpc.cgi> script in
your Bugzilla installation. For example, if your Bugzilla is at
C<bugzilla.yourdomain.com>, then your JSON-RPC client would access the
API via: C<http://bugzilla.yourdomain.com/jsonrpc.cgi>

Bugzilla only allows JSON-RPC requests over C<POST>. C<GET> requests
(or any other type of request, such as C<HEAD>) will be denied.

=head1 PARAMETERS

For JSON-RPC 1.0, the very first parameter should be an object containing
the named parameters. For example, if you were passing two named parameters,
one called C<foo> and the other called C<bar>, the C<params> element of
your JSON-RPC call would look like:

 "params": [{ "foo": 1, "bar": "something" }]

For JSON-RPC 1.1, you can pass parameters either in the above fashion
or using the standard named-parameters mechanism of JSON-RPC 1.1.

C<dateTime> fields are strings in the standard ISO-8601 format:
C<YYYY-MM-DDTHH:MM:SSZ>, where C<T> and C<Z> are a literal T and Z,
respectively. The "Z" means that all times are in UTC timezone--times are
always returned in UTC, and should be passed in as UTC. (Note: The JSON-RPC
interface currently also accepts non-UTC times for any values passed in, if
they include a time-zone specifier that follows the ISO-8601 standard, instead
of "Z" at the end. This behavior is expected to continue into the future, but
to be fully safe for forward-compatibility with all future versions of
Bugzilla, it is safest to pass in all times as UTC with the "Z" timezone
specifier.)

All other types are standard JSON types.

=head1 ERRORS

JSON-RPC 1.0 and JSON-RPC 1.1 both return an C<error> element when they
throw an error. In Bugzilla, the error contents look like:

 { message: 'Some message here', code: 123 }

So, for example, in JSON-RPC 1.0, an error response would look like:

 { 
   result: null, 
   error: { message: 'Some message here', code: 123 }, 
   id: 1
 }

Every error has a "code", as described in L<Bugzilla::WebService/ERRORS>.
Errors with a numeric C<code> higher than 100000 are errors thrown by
the JSON-RPC library that Bugzilla uses, not by Bugzilla.

=head1 SEE ALSO

L<Bugzilla::WebService>
