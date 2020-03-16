# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::OpenLDAPSec;

use 5.10.1;
use strict;
use warnings;

use parent qw(Bugzilla::Extension);

# This code for this is in ../extensions/OpenLDAPSec/lib/Util.pm
use Bugzilla::Extension::OpenLDAPSec::Util;

use Bugzilla::Util;
use Bugzilla::Constants;

use List::MoreUtils qw(any);

our $VERSION = '0.01';

# CC the appropriate lists:
# - public list for public bugs
# - insiders if it's a private bug or a private comment is in the mail
sub bugmail_recipients {
    my ($self, $args) = @_;
    my $recipients = $args->{recipients};
    my $bug        = $args->{bug};

    my $insider_group = new Bugzilla::Group({name => Bugzilla->params->{'insidergroup'}});

    my $insider_list = new Bugzilla::User({name => Bugzilla->params->{'insider_list'}});
    my $public_list = new Bugzilla::User({name => Bugzilla->params->{'public_list'}});

    return unless ( defined $insider_group && defined $insider_list && defined $public_list );

    if ( any { $_->id eq $insider_group->id } @{$bug->groups_in} ) {
        delete $recipients->{$public_list->id};
        $recipients->{$insider_list->id}->{+REL_CC} = 2;
    } else {
        # It's a public bug, add public list, it still won't get private comments
        $recipients->{$public_list->id}->{+REL_CC} = 2;

        # Is there a private comment? If so, add insider_list on CC
        my $comments = $bug->comments({after => $bug->lastdiffed, to => $bug->delta_ts});
        @$comments = grep { $_->type || $_->body =~ /\S/ } @$comments;
        if ( any { $_->is_private } @$comments ) {
            $recipients->{$insider_list->id}->{+REL_CC} = 2;
        }
    }
}

sub config_add_panels {
    my ($self, $args) = @_;
    my $modules = $args->{panel_modules};
    $modules->{OpenLDAPSec} = "Bugzilla::Extension::OpenLDAPSec::Config";
}

__PACKAGE__->NAME;
