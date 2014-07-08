# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugmailFilter::FakeField;

use strict;
use warnings;

use Bugzilla::Extension::BugmailFilter::Constants;

# object

sub new {
    my ($class, $params) = @_;
    return bless($params, $class);
}

sub name        { $_[0]->{name} }
sub description { $_[0]->{description} }

# static methods

sub fake_fields {
    my $cache = Bugzilla->request_cache->{bugmail_filter};
    if (!$cache->{fake_fields}) {
        my @fields;
        foreach my $rh (@{ FAKE_FIELD_NAMES() }) {
            push @fields, Bugzilla::Extension::BugmailFilter::FakeField->new($rh);
        }
        $cache->{fake_fields} = \@fields;
    }
    return $cache->{fake_fields};
}

sub tracking_flag_fields {
    my $cache = Bugzilla->request_cache->{bugmail_filter};
    if (!$cache->{tracking_flag_fields}) {
        require Bugzilla::Extension::TrackingFlags::Constants;
        my @fields;
        my $tracking_types = Bugzilla::Extension::TrackingFlags::Constants::FLAG_TYPES();
        foreach my $tracking_type (@$tracking_types) {
            push @fields, Bugzilla::Extension::BugmailFilter::FakeField->new({
                name        => 'tracking.' . $tracking_type->{name},
                description => $tracking_type->{description},
                sortkey     => $tracking_type->{sortkey},
            });
        }
        $cache->{tracking_flag_fields} = \@fields;
    }
    return $cache->{tracking_flag_fields};
}

1;
