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
use Date::Parse;
use DateTime;

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    Bugzilla->_json_server($self);
    $self->dispatch(WS_DISPATCH);
    $self->return_die_message(1);
    $self->json->allow_blessed(1);
    $self->json->convert_blessed(1);
    # Default to JSON-RPC 1.0
    $self->version(0);
    return $self;
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
        # str2time uses Time::Local internally, so I believe it should
        # always return seconds based on the *Unix* epoch, even if the
        # system doesn't use the Unix epoch.
        $retval = str2time($value) * 1000;
    }
    # XXX Will have to implement base64 if Bugzilla starts using it.

    return $retval;
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

    # This is the best time to do login checks.
    $self->handle_login();

    # If there are no parameters, we don't need to parse them.
    return $params if !ref $params;

    # JSON-RPC 1.0 requires all parameters to be passed as an array, so
    # we just pull out the first item and assume it's an object.
    if (ref $params eq 'ARRAY') {
        $params = $params->[0];
    }

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

    # Bugzilla::WebService packages call internal methods like
    # $self->_some_private_method. So we have to inherit from 
    # that class as well as this Server class.
    my $new_class = ref($self) . '::' . $pkg;
    my $isa_string = 'our @ISA = qw(' . ref($self) . " $pkg)";
    eval "package $new_class;$isa_string;";
    bless $self, $new_class;

    return $params;
}

sub _bz_convert_datetime {
    my ($self, $time) = @_;
    my $dt = DateTime->from_epoch(epoch => ($time / 1000), 
                                  time_zone => Bugzilla->local_timezone);
    return $dt->strftime('%Y-%m-%d %T');
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
B<UNSTABLE>. If you want a stable API, please use the
C<XML-RPC|Bugzilla::WebService::Server::XMLRPC> interface.

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

C<dateTime> fields are represented as an integer number of microseconds
since the Unix epoch (January 1, 1970 UTC). They are always in the UTC
timezone.

All other types are standard JSON types.

=head1 ERRORS

All errors thrown by Bugzilla itself have 100000 added to their numeric
code. So, if the documentation says that an error is C<302>, then
it will be C<100302> when it is thrown via JSON-RPC.

Errors less than 100000 are errors thrown by the JSON-RPC library that
Bugzilla uses, not by Bugzilla.

=head1 SEE ALSO

=head2 Server Types

=over

=item L<Bugzilla::WebService::Server::XMLRPC>

=item L<Bugzilla::WebService::Server::JSONRPC>

=back

=head2 WebService Methods

=over

=item L<Bugzilla::WebService::Bug>

=item L<Bugzilla::WebService::Bugzilla>

=item L<Bugzilla::WebService::Product>

=item L<Bugzilla::WebService::User>

=back
