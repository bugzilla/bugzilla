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
# The Initial Developer of the Original Code is Frédéric Buclin.
# Portions created by Frédéric Buclin are Copyright (C) 2007
# Frédéric Buclin. All Rights Reserved.
#
# Contributor(s): Frédéric Buclin <LpSolit@gmail.com>

use strict;

package Bugzilla::Status;

use base qw(Bugzilla::Object);

################################
#####   Initialization     #####
################################

use constant DB_TABLE => 'bug_status';

use constant DB_COLUMNS => qw(
    id
    value
    sortkey
    isactive
    is_open
);

use constant NAME_FIELD => 'value';
use constant LIST_ORDER => 'sortkey, value';

###############################
#####     Accessors        ####
###############################

sub name      { return $_[0]->{'value'};    }
sub sortkey   { return $_[0]->{'sortkey'};  }
sub is_active { return $_[0]->{'isactive'}; }
sub is_open   { return $_[0]->{'is_open'};  }

###############################
#####       Methods        ####
###############################

sub can_change_to {
    my $self = shift;
    my $dbh = Bugzilla->dbh;

    if (!defined $self->{'can_change_to'}) {
        my $new_status_ids = $dbh->selectcol_arrayref('SELECT new_status
                                                         FROM status_workflow
                                                   INNER JOIN bug_status
                                                           ON id = new_status
                                                        WHERE isactive = 1
                                                          AND old_status = ?',
                                                        undef, $self->id);

        $self->{'can_change_to'} = Bugzilla::Status->new_from_list($new_status_ids);
    }

    return $self->{'can_change_to'};
}


1;

__END__

=head1 NAME

Bugzilla::Status - Bug status class.

=head1 SYNOPSIS

    use Bugzilla::Status;

    my $bug_status = new Bugzilla::Status({name => 'ASSIGNED'});
    my $bug_status = new Bugzilla::Status(4);

=head1 DESCRIPTION

Status.pm represents a bug status object. It is an implementation
of L<Bugzilla::Object>, and thus provides all methods that
L<Bugzilla::Object> provides.

The methods that are specific to C<Bugzilla::Status> are listed
below.

=head1 METHODS

=over

=item C<can_change_to>

 Description: Returns the list of active statuses a bug can be changed to
              given the current bug status.

 Params:      none.

 Returns:     A list of Bugzilla::Status objects.

=back

=cut
