# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This is the base class for $self in WebService API method calls. For the
# actual RPC server, see Bugzilla::API::Server and its subclasses.

package Bugzilla::API::1_0::Resource;

use 5.10.1;
use strict;
use warnings;

use Moo;

#####################
# Default Constants #
#####################

# Used by the server to convert incoming date fields apprpriately.
use constant DATE_FIELDS => {};

# Used by the server to convert incoming base64 fields appropriately.
use constant BASE64_FIELDS => {};

# For some methods, we shouldn't call Bugzilla->login before we call them
use constant LOGIN_EXEMPT => { };

# Used to allow methods to be called in the JSON-RPC WebService via GET.
# Methods that can modify data MUST not be listed here.
use constant READ_ONLY => ();

# Whitelist of methods that a client is allowed to access when making
# an API call.
use constant PUBLIC_METHODS => ();

# Array of path mappings for method names for the API. Also describes
# how path values are mapped to method parameters values.
use constant REST_RESOURCES => [];

##################
# Public Methods #
##################

sub login_exempt {
    my ($class, $method) = @_;
    return $class->LOGIN_EXEMPT->{$method};
}

1;

__END__

=head1 NAME

Bugzilla::API::1_0::Resource - The Web Service Resource interface to Bugzilla

=head1 DESCRIPTION

This is the standard API for external programs that want to interact
with Bugzilla. It provides endpoints or methods in various modules.

You can interact with this API via L<REST|Bugzilla::API::1_0::Server>.

=head1 CALLING METHODS

Methods are grouped into "packages", like C<Bug> for
L<Bugzilla::API::1_0::Resource::Bug>. So, for example,
L<Bugzilla::API::1_0::Resource::Bug/get>, is called as C<Bug.get>.

For REST, the "package" is more determined by the path used to access the
resource. See each relevant method for specific details on how to access via REST.

=head1 USAGE

Full documentation on how to use the Bugzilla API can be found at
L<https://bugzilla.readthedocs.org/en/latest/api/index.html>.

=head1 ERRORS

If a particular API call fails, it will throw an error in the appropriate format
providing at least a numeric error code and descriptive text for the error.

The various errors that functions can throw are specified by the
documentation of those functions.

Each error that Bugzilla can throw has a specific numeric code that will
not change between versions of Bugzilla. If your code needs to know what
error Bugzilla threw, use the numeric code. Don't try to parse the
description, because that may change from version to version of Bugzilla.

Note that if you display the error to the user in an HTML program, make
sure that you properly escape the error, as it will not be HTML-escaped.

=head2 Transient vs. Fatal Errors

If the error code is a number greater than 0, the error is considered
"transient," which means that it was an error made by the user, not
some problem with Bugzilla itself.

If the error code is a number less than 0, the error is "fatal," which
means that it's some error in Bugzilla itself that probably requires
administrative attention.

Negative numbers and positive numbers don't overlap. That is, if there's
an error 302, there won't be an error -302.

=head2 Unknown Errors

Sometimes a function will throw an error that doesn't have a specific
error code. In this case, the code will be C<-32000> if it's a "fatal"
error, and C<32000> if it's a "transient" error.

=head1 SEE ALSO

=head2 API Resource Modules

=over

=item L<Bugzilla::API::1_0::Resource::Bug>

=item L<Bugzilla::API::1_0::Resource::Bugzilla>

=item L<Bugzilla::API::1_0::Resource::Classification>

=item L<Bugzilla::API::1_0::Resource::FlagType>

=item L<Bugzilla::API::1_0::Resource::Component>

=item L<Bugzilla::API::1_0::Resource::Group>

=item L<Bugzilla::API::1_0::Resource::Product>

=item L<Bugzilla::API::1_0::Resource::User>

=back

=head1 B<Methods in need of POD>

=over

=item login_exempt

=back
