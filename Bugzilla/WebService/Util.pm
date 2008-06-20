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
# The Initial Developer of the Original Code is Everything Solved.
# Portions created by Everything Solved are Copyright (C) 2008
# Everything Solved. All Rights Reserved.
#
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::WebService::Util;
use strict;

use base qw(Exporter);

our @EXPORT_OK = qw(filter);

sub filter ($$) {
    my ($params, $hash) = @_;
    my %newhash = %$hash;
    my %include = map { $_ => 1 } @{ $params->{'include_fields'} || [] };
    my %exclude = map { $_ => 1 } @{ $params->{'exclude_fields'} || [] };

    foreach my $key (keys %$hash) {
        if (defined $params->{include_fields}) {
            delete $newhash{$key} if !$include{$key};
        }
        if (defined $params->{exclude_fields}) {
            delete $newhash{$key} if $exclude{$key};
        }
    }

    return \%newhash;
}

__END__

=head1 NAME

Bugzilla::WebService::Util - Utility functions used inside of the WebService
code.

=head1 DESCRIPTION

This is somewhat like L<Bugzilla::Util>, but these functions are only used
internally in the WebService code.

=head1 SYNOPSIS

 filter({ include_fields => ['id', 'name'], 
          exclude_fields => ['name'] }, $hash);

=head1 METHODS

=over

=item C<filter_fields>

This helps implement the C<include_fields> and C<exclude_fields> arguments
of WebService methods. Given a hash (the second argument to this subroutine),
this will remove any keys that are I<not> in C<include_fields> and then remove
any keys that I<are> in C<exclude_fields>.

=back
