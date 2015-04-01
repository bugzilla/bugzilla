# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugModal::MonkeyPatches;
1;

package Bugzilla::Bug;
use strict;
use warnings;

use Bugzilla::Attachment;

sub active_attachments {
    my ($self) = @_;
    return [] if $self->{error};
    return $self->{active_attachments} //= Bugzilla::Attachment->get_attachments_by_bug(
        $self, { exclude_obsolete => 1, preload => 1 });
}

1;

package Bugzilla::User;
use strict;
use warnings;

sub moz_nick {
    my ($self) = @_;
    return $1 if $self->name =~ /:(.+?)\b/;
    return $self->name if $self->name;
    $self->login =~ /^([^\@]+)\@/;
    return $1;
}

1;

package Bugzilla::Attachment;
use strict;
use warnings;

sub is_image {
    my ($self) = @_;
    return substr($self->contenttype, 0, 6) eq 'image/';
}

1;
