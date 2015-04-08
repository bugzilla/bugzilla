# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::API::1_0::Resource::Bugzilla;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::API::1_0::Util;

use Bugzilla::Constants;
use Bugzilla::Util qw(datetime_from);
use Bugzilla::Util qw(trick_taint);

use DateTime;
use Moo;

extends 'Bugzilla::API::1_0::Resource';

##############
# Constants  #
##############

# Basic info that is needed before logins
use constant LOGIN_EXEMPT => {
    parameters => 1,
    timezone => 1,
    version => 1,
};

use constant READ_ONLY => qw(
    extensions
    parameters
    timezone
    time
    version
);

use constant PUBLIC_METHODS => qw(
    extensions
    last_audit_time
    parameters
    time
    timezone
    version
);

# Logged-out users do not need to know more than that.
use constant PARAMETERS_LOGGED_OUT => qw(
    maintainer
    requirelogin
);

# These parameters are guessable from the web UI when the user
# is logged in. So it's safe to access them.
use constant PARAMETERS_LOGGED_IN => qw(
    allowemailchange
    attachment_base
    commentonchange_resolution
    commentonduplicate
    cookiepath
    defaultopsys
    defaultplatform
    defaultpriority
    defaultseverity
    duplicate_or_move_bug_status
    emailregexpdesc
    emailsuffix
    letsubmitterchoosemilestone
    letsubmitterchoosepriority
    mailfrom
    maintainer
    maxattachmentsize
    maxlocalattachment
    musthavemilestoneonaccept
    noresolveonopenblockers
    password_complexity
    rememberlogin
    requirelogin
    search_allow_no_criteria
    urlbase
    use_see_also
    useclassification
    usemenuforusers
    useqacontact
    usestatuswhiteboard
    usetargetmilestone
);

sub REST_RESOURCES {
    my $rest_resources = [
        qr{^/version$}, {
            GET  => {
                method => 'version'
            }
        },
        qr{^/extensions$}, {
            GET => {
                method => 'extensions'
            }
        },
        qr{^/timezone$}, {
            GET => {
                method => 'timezone'
            }
        },
        qr{^/time$}, {
            GET => {
                method => 'time'
            }
        },
        qr{^/last_audit_time$}, {
            GET => {
                method => 'last_audit_time'
            }
        },
        qr{^/parameters$}, {
            GET => {
                method => 'parameters'
            }
        }
    ];
    return $rest_resources;
}

############
# Methods  #
############

sub version {
    my $self = shift;
    return { version => as_string(BUGZILLA_VERSION) };
}

sub extensions {
    my $self = shift;

    my %retval;
    foreach my $extension (@{ Bugzilla->extensions }) {
        my $version = $extension->VERSION || 0;
        my $name    = $extension->NAME;
        $retval{$name}->{version} = as_string($version);
    }
    return { extensions => \%retval };
}

sub timezone {
    my $self = shift;
    # All Webservices return times in UTC; Use UTC here for backwards compat.
    return { timezone => as_string("+0000") };
}

sub time {
    my ($self) = @_;
    # All Webservices return times in UTC; Use UTC here for backwards compat.
    # Hardcode values where appropriate
    my $dbh = Bugzilla->dbh;

    my $db_time = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    $db_time = datetime_from($db_time, 'UTC');
    my $now_utc = DateTime->now();

    return {
        db_time  => as_datetime($db_time),
        web_time => as_datetime($now_utc),
    };
}

sub last_audit_time {
    my ($self, $params) = validate(@_, 'class');
    my $dbh = Bugzilla->dbh;

    my $sql_statement = "SELECT MAX(at_time) FROM audit_log";
    my $class_values =  $params->{class};
    my @class_values_quoted;
    foreach my $class_value (@$class_values) {
        push (@class_values_quoted, $dbh->quote($class_value))
            if $class_value =~ /^Bugzilla(::[a-zA-Z0-9_]+)*$/;
    }

    if (@class_values_quoted) {
        $sql_statement .= " WHERE " . $dbh->sql_in('class', \@class_values_quoted);
    }

    my $last_audit_time = $dbh->selectrow_array("$sql_statement");

    # All Webservices return times in UTC; Use UTC here for backwards compat.
    # Hardcode values where appropriate
    $last_audit_time = datetime_from($last_audit_time, 'UTC');

    return {
        last_audit_time => as_datetime($last_audit_time)
    };
}

sub parameters {
    my ($self, $args) = @_;
    my $user = Bugzilla->login();
    my $params = Bugzilla->params;
    $args ||= {};

    my @params_list = $user->in_group('tweakparams')
                      ? keys(%$params)
                      : $user->id ? PARAMETERS_LOGGED_IN : PARAMETERS_LOGGED_OUT;

    my %parameters;
    foreach my $param (@params_list) {
        next unless filter_wants($args, $param);
        $parameters{$param} = as_string($params->{$param});
    }

    return { parameters => \%parameters };
}

1;

__END__

=head1 NAME

Bugzilla::API::1_0::Resource::Bugzilla - Global functions for the webservice interface.

=head1 DESCRIPTION

This provides functions that tell you about Bugzilla in general.

=head1 METHODS

=head2 version

=over

=item B<Description>

Returns the current version of Bugzilla.

=item B<REST>

GET /rest/version

The returned data format is the same as below.

=item B<Params> (none)

=item B<Returns>

A hash with a single item, C<version>, that is the version as a
string.

=item B<Errors> (none)

=item B<History>

=over

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=head2 extensions

=over

=item B<Description>

Gets information about the extensions that are currently installed and enabled
in this Bugzilla.

=item B<REST>

GET /rest/extensions

The returned data format is the same as below.

=item B<Params> (none)

=item B<Returns>

A hash with a single item, C<extensions>. This points to a hash. I<That> hash
contains the names of extensions as keys, and the values are a hash.
That hash contains a single key C<version>, which is the version of the
extension, or C<0> if the extension hasn't defined a version.

The return value looks something like this:

 extensions => {
     Example => {
         version => '3.6',
     },
     BmpConvert => {
         version => '1.0',
     },
 }

=item B<History>

=over

=item Added in Bugzilla B<3.2>.

=item As of Bugzilla B<3.6>, the names of extensions are canonical names
that the extensions define themselves. Before 3.6, the names of the
extensions depended on the directory they were in on the Bugzilla server.

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=head2 timezone

B<DEPRECATED> This method may be removed in a future version of Bugzilla.
Use L</time> instead.

=over

=item B<Description>

Returns the timezone that Bugzilla expects dates and times in.

=item B<REST>

GET /rest/timezone

The returned data format is the same as below.

=item B<Params> (none)

=item B<Returns>

A hash with a single item, C<timezone>, that is the timezone offset as a
string in (+/-)XXXX (RFC 2822) format.

=item B<History>

=over

=item As of Bugzilla B<3.6>, the timezone returned is always C<+0000>
(the UTC timezone).

=item REST API call added in Bugzilla B<5.0>.

=back

=back


=head2 time

=over

=item B<Description>

Gets information about what time the Bugzilla server thinks it is, and
what timezone it's running in.

=item B<REST>

GET /rest/time

The returned data format is the same as below.

=item B<Params> (none)

=item B<Returns>

A struct with the following items:

=over

=item C<db_time>

C<dateTime> The current time in UTC, according to the Bugzilla
I<database server>.

Note that Bugzilla assumes that the database and the webserver are running
in the same time zone. However, if the web server and the database server
aren't synchronized for some reason, I<this> is the time that you should
rely on for doing searches and other input to the WebService.

=item C<web_time>

C<dateTime> This is the current time in UTC, according to Bugzilla's
I<web server>.

This might be different by a second from C<db_time> since this comes from
a different source. If it's any more different than a second, then there is
likely some problem with this Bugzilla instance. In this case you should
rely on the C<db_time>, not the C<web_time>.

=back

=item B<History>

=over

=item Added in Bugzilla B<3.4>.

=item As of Bugzilla B<3.6>, this method returns all data as though the server
were in the UTC timezone, instead of returning information in the server's
local timezone.

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=head2 parameters

=over

=item B<Description>

Returns parameter values currently used in this Bugzilla.

=item B<REST>

GET /rest/parameters

The returned data format is the same as below.

=item B<Params> (none)

=item B<Returns>

A hash with a single item C<parameters> which contains a hash with
the name of the parameters as keys and their value as values. All
values are returned as strings.
The list of parameters returned by this method depends on the user
credentials:

A logged-out user can only access the C<maintainer> and C<requirelogin> parameters.

A logged-in user can access the following parameters (listed alphabetically):
    C<allowemailchange>,
    C<attachment_base>,
    C<commentonchange_resolution>,
    C<commentonduplicate>,
    C<cookiepath>,
    C<defaultopsys>,
    C<defaultplatform>,
    C<defaultpriority>,
    C<defaultseverity>,
    C<duplicate_or_move_bug_status>,
    C<emailregexpdesc>,
    C<emailsuffix>,
    C<letsubmitterchoosemilestone>,
    C<letsubmitterchoosepriority>,
    C<mailfrom>,
    C<maintainer>,
    C<maxattachmentsize>,
    C<maxlocalattachment>,
    C<musthavemilestoneonaccept>,
    C<noresolveonopenblockers>,
    C<password_complexity>,
    C<rememberlogin>,
    C<requirelogin>,
    C<search_allow_no_criteria>,
    C<urlbase>,
    C<use_see_also>,
    C<useclassification>,
    C<usemenuforusers>,
    C<useqacontact>,
    C<usestatuswhiteboard>,
    C<usetargetmilestone>.

A user in the tweakparams group can access all existing parameters.
New parameters can appear or obsolete parameters can disappear depending
on the version of Bugzilla and on extensions being installed.
The list of parameters returned by this method is not stable and will
never be stable.

=item B<History>

=over

=item Added in Bugzilla B<4.4>.

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=head2 last_audit_time

=over

=item B<Description>

Gets the latest time of the audit_log table.

=item B<REST>

GET /rest/last_audit_time

The returned data format is the same as below.

=item B<Params>

You can pass the optional parameter C<class> to get the maximum for only
the listed classes.

=over

=item C<class> (array) - An array of strings representing the class names.

B<Note:> The class names are defined as "Bugzilla::<class_name>". For the product
use Bugzilla:Product.

=back

=item B<Returns>

A hash with a single item, C<last_audit_time>, that is the maximum of the
at_time from the audit_log.

=item B<Errors> (none)

=item B<History>

=over

=item Added in Bugzilla B<4.4>.

=item REST API call added in Bugzilla B<5.0>.

=back

=back

=head1 B<Methods in need of POD>

=over

=item REST_RESOURCES

=back
