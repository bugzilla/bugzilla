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
#                 Mads Bondo Dydensborg <mbd@dbc.dk>

package Bugzilla::WebService::Bugzilla;

use strict;
use base qw(Bugzilla::WebService);
use Bugzilla::Constants;

use DateTime;

# Basic info that is needed before logins
use constant LOGIN_EXEMPT => {
    timezone => 1,
    version => 1,
};

sub version {
    my $self = shift;
    return { version => $self->type('string', BUGZILLA_VERSION) };
}

sub extensions {
    my $self = shift;

    my %retval;
    foreach my $extension (@{ Bugzilla->extensions }) {
        my $version = $extension->VERSION || 0;
        my $name    = $extension->NAME;
        $retval{$name}->{version} = $self->type('string', $version);
    }
    return { extensions => \%retval };
}

sub timezone {
    my $self = shift;
    my $offset = Bugzilla->local_timezone->offset_for_datetime(DateTime->now());
    $offset = (($offset / 60) / 60) * 100;
    $offset = sprintf('%+05d', $offset);
    return { timezone => $self->type('string', $offset) };
}

sub time {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;

    my $db_time = $dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
    my $now_utc = DateTime->now();

    my $tz = Bugzilla->local_timezone;
    my $now_local = $now_utc->clone->set_time_zone($tz);
    my $tz_offset = $tz->offset_for_datetime($now_local);

    return {
        db_time       => $self->type('dateTime', $db_time),
        web_time      => $self->type('dateTime', $now_local),
        web_time_utc  => $self->type('dateTime', $now_utc),
        tz_name       => $self->type('string', $tz->name),
        tz_offset     => $self->type('string', 
                                     $tz->offset_as_string($tz_offset)),
        tz_short_name => $self->type('string', 
                                     $now_local->time_zone_short_name),
    };
}

1;

__END__

=head1 NAME

Bugzilla::WebService::Bugzilla - Global functions for the webservice interface.

=head1 DESCRIPTION

This provides functions that tell you about Bugzilla in general.

=head1 METHODS

See L<Bugzilla::WebService> for a description of how parameters are passed,
and what B<STABLE>, B<UNSTABLE>, and B<EXPERIMENTAL> mean.

=over

=item C<version>

B<STABLE>

=over

=item B<Description>

Returns the current version of Bugzilla.

=item B<Params> (none)

=item B<Returns>

A hash with a single item, C<version>, that is the version as a
string.

=item B<Errors> (none)

=back

=item C<extensions>

B<EXPERIMENTAL>

=over

=item B<Description>

Gets information about the extensions that are currently installed and enabled
in this Bugzilla.

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

=back

=back

=item C<timezone>

B<DEPRECATED> This method may be removed in a future version of Bugzilla.
Use L</time> instead.

=over

=item B<Description>

Returns the timezone of the server Bugzilla is running on. This is
important because all dates/times that the webservice interface
returns will be in this timezone.

=item B<Params> (none)

=item B<Returns>

A hash with a single item, C<timezone>, that is the timezone offset as a
string in (+/-)XXXX (RFC 2822) format.

=back


=item C<time>

B<UNSTABLE>

=over

=item B<Description>

Gets information about what time the Bugzilla server thinks it is, and
what timezone it's running in.

=item B<Params> (none)

=item B<Returns>

A struct with the following items:

=over

=item C<db_time>

C<dateTime> The current time in Bugzilla's B<local time zone>, according 
to the Bugzilla I<database server>.

Note that Bugzilla assumes that the database and the webserver are running
in the same time zone. However, if the web server and the database server
aren't synchronized for some reason, I<this> is the time that you should
rely on for doing searches and other input to the WebService.

=item C<web_time>

C<dateTime> This is the current time in Bugzilla's B<local time zone>, 
according to Bugzilla's I<web server>.

This might be different by a second from C<db_time> since this comes from
a different source. If it's any more different than a second, then there is
likely some problem with this Bugzilla instance. In this case you should
rely on the C<db_time>, not the C<web_time>.

=item C<web_time_utc>

The same as C<web_time>, but in the B<UTC> time zone instead of the local
time zone.

=item C<tz_name>

C<string> The long name of the time zone that the Bugzilla web server is 
in. Will usually look something like: C<America/Los Angeles>

=item C<tz_short_name>

C<string> The "short name" of the time zone that the Bugzilla web server
is in. This should only be used for display, and not relied on for your
programs, because different time zones can have the same short name.
(For example, there are two C<EST>s.)

This will look something like: C<PST>.

=item C<tz_offset>

C<string> The timezone offset as a string in (+/-)XXXX (RFC 2822) format.

=back

=item B<History>

=over

=item Added in Bugzilla B<3.4>.

=back

=back


=back
