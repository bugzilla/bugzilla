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
# The Original Code is the LimitedEmail Extension.

#
# The Initial Developer of the Original Code is the Mozilla Foundation
# Portions created by the Initial Developers are Copyright (C) 2011 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Byron Jones <bjones@mozilla.com>

package Bugzilla::Extension::LimitedEmail;
use strict;
use base qw(Bugzilla::Extension);

our $VERSION = '1';

use Bugzilla::User;

sub bugmail_recipients {
    my ($self, $args) = @_;
    foreach my $user_id (keys %{$args->{recipients}}) {
        my $user = Bugzilla::User->new($user_id);
        if (!deliver_to($user->email)) {
            delete $args->{recipients}{$user_id};
        }
    }
}

sub mailer_before_send {
    my ($self, $args) = @_;
    my $email = $args->{email};
    if (!deliver_to($email->{header}->header('to'))) {
        $email->{header}->header_set(to => Bugzilla::Extension::LimitedEmail::BLACK_HOLE);
    }
}

sub deliver_to {
    my $email = shift;
    my $ra_filters = Bugzilla::Extension::LimitedEmail::FILTERS;
    foreach my $re (@$ra_filters) {
        if ($email =~ $re) {
            return 1;
        }
    }
    return 0;
}

__PACKAGE__->NAME;
