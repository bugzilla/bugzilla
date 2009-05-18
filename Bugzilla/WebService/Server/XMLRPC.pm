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
# The Original Code is the Bugzilla Bug Tracking System.
#
# Contributor(s): Marc Schumann <wurblzap@gmail.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Rosie Clarkson <rosie.clarkson@planningportal.gov.uk>
#                 
# Portions © Crown copyright 2009 - Rosie Clarkson (development@planningportal.gov.uk) for the Planning Portal

package Bugzilla::WebService::Server::XMLRPC;

use strict;
use XMLRPC::Transport::HTTP;
use Bugzilla::WebService::Server;
our @ISA = qw(XMLRPC::Transport::HTTP::CGI Bugzilla::WebService::Server);

use Bugzilla::WebService::Constants;

sub initialize {
    my $self = shift;
    my %retval = $self->SUPER::initialize(@_);
    $retval{'serializer'}   = Bugzilla::XMLRPC::Serializer->new;
    $retval{'deserializer'} = Bugzilla::XMLRPC::Deserializer->new;
    $retval{'dispatch_with'} = WS_DISPATCH;
    return %retval;
}

sub make_response {
    my $self = shift;

    $self->SUPER::make_response(@_);

    # XMLRPC::Transport::HTTP::CGI doesn't know about Bugzilla carrying around
    # its cookies in Bugzilla::CGI, so we need to copy them over.
    foreach (@{Bugzilla->cgi->{'Bugzilla_cookie_list'}}) {
        $self->response->headers->push_header('Set-Cookie', $_);
    }
}

sub datetime_format {
    my ($self, $date_string) = @_;

    my $time = str2time($date_string);
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime $time;
    # This format string was stolen from SOAP::Utils->format_datetime,
    # which doesn't work but which has almost the right format string.
    my $iso_datetime = sprintf('%d%02d%02dT%02d:%02d:%02d',
        $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
    return $iso_datetime;
}

sub handle_login {
    my ($self, $classes, $action, $uri, $method) = @_;
    my $class = $classes->{$uri};
    my $full_method = $uri . "." . $method;
    $self->SUPER::handle_login($class, $method, $full_method);
    return;
}

1;

# This exists to validate input parameters (which XMLRPC::Lite doesn't do)
# and also, in some cases, to more-usefully decode them.
package Bugzilla::XMLRPC::Deserializer;
use strict;
# We can't use "use base" because XMLRPC::Serializer doesn't return
# a true value.
eval { require XMLRPC::Lite; };
our @ISA = qw(XMLRPC::Deserializer);

use Bugzilla::Error;

# Some method arguments need to be converted in some way, when they are input.
sub decode_value {
    my $self = shift;
    my ($type) = @{ $_[0] };
    my $value = $self->SUPER::decode_value(@_);
    
    # We only validate/convert certain types here.
    return $value if $type !~ /^(?:int|i4|boolean|double|dateTime\.iso8601)$/;
    
    # Though the XML-RPC standard doesn't allow an empty <int>,
    # <double>,or <dateTime.iso8601>,  we do, and we just say
    # "that's undef".
    if (grep($type eq $_, qw(int double dateTime))) {
        return undef if $value eq '';
    }
    
    my $validator = $self->_validation_subs->{$type};
    if (!$validator->($value)) {
        ThrowUserError('xmlrpc_invalid_value',
                       { type => $type, value => $value });
    }
    
    # We convert dateTimes to a DB-friendly date format.
    if ($type eq 'dateTime.iso8601') {
        # We leave off the $ from the end of this regex to allow for possible
        # extensions to the XML-RPC date standard.
        $value =~ /^(\d{4})(\d{2})(\d{2})T(\d{2}):(\d{2}):(\d{2})/;
        $value = "$1-$2-$3 $4:$5:$6";
    }

    return $value;
}

sub _validation_subs {
    my $self = shift;
    return $self->{_validation_subs} if $self->{_validation_subs};
    # The only place that XMLRPC::Lite stores any sort of validation
    # regex is in XMLRPC::Serializer. We want to re-use those regexes here.
    my $lookup = Bugzilla::XMLRPC::Serializer->new->typelookup;
    
    # $lookup is a hash whose values are arrayrefs, and whose keys are the
    # names of types. The second item of each arrayref is a subroutine
    # that will do our validation for us.
    my %validators = map { $_ => $lookup->{$_}->[1] } (keys %$lookup);
    # Add a boolean validator
    $validators{'boolean'} = sub {$_[0] =~ /^[01]$/};
    # Some types have multiple names, or have a different name in
    # XMLRPC::Serializer than their standard XML-RPC name.
    $validators{'dateTime.iso8601'} = $validators{'dateTime'};
    $validators{'i4'} = $validators{'int'};
    
    $self->{_validation_subs} = \%validators;
    return \%validators;
}

1;

# This package exists to fix a UTF-8 bug in SOAP::Lite.
# See http://rt.cpan.org/Public/Bug/Display.html?id=32952.
package Bugzilla::XMLRPC::Serializer;
use strict;
# We can't use "use base" because XMLRPC::Serializer doesn't return
# a true value.
eval { require XMLRPC::Lite; };
our @ISA = qw(XMLRPC::Serializer);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    # This fixes UTF-8.
    $self->{'_typelookup'}->{'base64'} =
        [10, sub { !utf8::is_utf8($_[0]) && $_[0] =~ /[^\x09\x0a\x0d\x20-\x7f]/},
        'as_base64'];
    # This makes arrays work right even though we're a subclass.
    # (See http://rt.cpan.org//Ticket/Display.html?id=34514)
    $self->{'_encodingStyle'} = '';
    return $self;
}

sub as_string {
    my $self = shift;
    my ($value) = @_;
    # Something weird happens with XML::Parser when we have upper-ASCII 
    # characters encoded as UTF-8, and this fixes it.
    utf8::encode($value) if utf8::is_utf8($value) 
                            && $value =~ /^[\x00-\xff]+$/;
    return $self->SUPER::as_string($value);
}

# Here the XMLRPC::Serializer is extended to use the XMLRPC nil extension.
sub encode_object {
    my $self = shift;
    my @encoded = $self->SUPER::encode_object(@_);

    return $encoded[0]->[0] eq 'nil'
        ? ['value', {}, [@encoded]]
        : @encoded;
}

sub BEGIN {
    no strict 'refs';
    for my $type (qw(double i4 int dateTime)) {
        my $method = 'as_' . $type;
        *$method = sub {
            my ($self, $value) = @_;
            if (!defined($value)) {
                return as_nil();
            }
            else {
                my $super_method = "SUPER::$method";
                return $self->$super_method($value);
            }
        }
    }
}

sub as_nil {
    return ['nil', {}];
}

1;
