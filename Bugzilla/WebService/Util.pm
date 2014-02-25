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
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by the Initial Developer are Copyright (C) 2008
# the Initial Developer. All Rights Reserved.
#
# Contributor(s): 
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::WebService::Util;
use strict;

use Bugzilla::Flag;
use Bugzilla::FlagType;
use Bugzilla::Error;

use Storable qw(dclone);

use base qw(Exporter);

# We have to "require", not "use" this, because otherwise it tries to
# use features of Test::More during import().
require Test::Taint;

our @EXPORT_OK = qw(
    extract_flags
    filter
    filter_wants
    taint_data
    validate
    translate
    params_to_objects
    fix_credentials
);

sub extract_flags {
    my ($flags, $bug, $attachment) = @_;
    my (@new_flags, @old_flags);

    my $flag_types    = $attachment ? $attachment->flag_types : $bug->flag_types;
    my $current_flags = $attachment ? $attachment->flags : $bug->flags;

    # Copy the user provided $flags as we may call extract_flags more than
    # once when editing multiple bugs or attachments.
    my $flags_copy = dclone($flags);

    foreach my $flag (@$flags_copy) {
        my $id      = $flag->{id};
        my $type_id = $flag->{type_id};

        my $new  = delete $flag->{new};
        my $name = delete $flag->{name};

        if ($id) {
            my $flag_obj = grep($id == $_->id, @$current_flags);
            $flag_obj || ThrowUserError('object_does_not_exist',
                                        { class => 'Bugzilla::Flag', id => $id });
        }
        elsif ($type_id) {
            my $type_obj = grep($type_id == $_->id, @$flag_types);
            $type_obj || ThrowUserError('object_does_not_exist',
                                        { class => 'Bugzilla::FlagType', id => $type_id });
            if (!$new) {
                my @flag_matches = grep($type_id == $_->type->id, @$current_flags);
                @flag_matches > 1 && ThrowUserError('flag_not_unique',
                                                     { value => $type_id });
                if (!@flag_matches) {
                    delete $flag->{id};
                }
                else {
                    delete $flag->{type_id};
                    $flag->{id} = $flag_matches[0]->id;
                }
            }
        }
        elsif ($name) {
            my @type_matches = grep($name eq $_->name, @$flag_types);
            @type_matches > 1 && ThrowUserError('flag_type_not_unique',
                                                { value => $name });
            @type_matches || ThrowUserError('object_does_not_exist',
                                            { class => 'Bugzilla::FlagType', name => $name });
            if ($new) {
                delete $flag->{id};
                $flag->{type_id} = $type_matches[0]->id;
            }
            else {
                my @flag_matches = grep($name eq $_->type->name, @$current_flags);
                @flag_matches > 1 && ThrowUserError('flag_not_unique', { value => $name });
                if (@flag_matches) {
                    $flag->{id} = $flag_matches[0]->id;
                }
                else {
                    delete $flag->{id};
                    $flag->{type_id} = $type_matches[0]->id;
                }
            }
        }

        if ($flag->{id}) {
            push(@old_flags, $flag);
        }
        else {
            push(@new_flags, $flag);
        }
    }

    return (\@old_flags, \@new_flags);
}

sub filter ($$;$) {
    my ($params, $hash, $prefix) = @_;
    my %newhash = %$hash;

    foreach my $key (keys %$hash) {
        delete $newhash{$key} if !filter_wants($params, $key, $prefix);
    }

    return \%newhash;
}

sub filter_wants ($$;$) {
    my ($params, $field, $prefix) = @_;

    # Since this is operation is resource intensive, we will cache the results
    # This assumes that $params->{*_fields} doesn't change between calls
    my $cache = Bugzilla->request_cache->{filter_wants} ||= {};
    $field = "${prefix}.${field}" if $prefix;

    if (exists $cache->{$field}) {
        return $cache->{$field};
    }

    my %include = map { $_ => 1 } @{ $params->{'include_fields'} || [] };
    my %exclude = map { $_ => 1 } @{ $params->{'exclude_fields'} || [] };

    my $wants = 1;
    if (defined $params->{exclude_fields} && $exclude{$field}) {
        $wants = 0;
    }
    elsif (defined $params->{include_fields} && !$include{$field}) {
        if ($prefix) {
            # Include the field if the parent is include (and this one is not excluded)
            $wants = 0 if !$include{$prefix};
        }
        else {
            # We want to include this if one of the sub keys is included
            my $key = $field . '.';
            my $len = length($key);
            $wants = 0 if ! grep { substr($_, 0, $len) eq $key  } keys %include;
        }
    }

    $cache->{$field} = $wants;
    return $wants;
}

sub taint_data {
    my @params = @_;
    return if !@params;
    # Though this is a private function, it hasn't changed since 2004 and
    # should be safe to use, and prevents us from having to write it ourselves
    # or require another module to do it.
    Test::Taint::_deeply_traverse(\&_delete_bad_keys, \@params);
    Test::Taint::taint_deeply(\@params);
}

sub _delete_bad_keys {
    foreach my $item (@_) {
        next if ref $item ne 'HASH';
        foreach my $key (keys %$item) {
            # Making something a hash key always untaints it, in Perl.
            # However, we need to validate our argument names in some way.
            # We know that all hash keys passed in to the WebService will 
            # match \w+, so we delete any key that doesn't match that.
            if ($key !~ /^\w+$/) {
                delete $item->{$key};
            }
        }
    }
    return @_;
}

sub validate  {
    my ($self, $params, @keys) = @_;

    # If $params is defined but not a reference, then we weren't
    # sent any parameters at all, and we're getting @keys where
    # $params should be.
    return ($self, undef) if (defined $params and !ref $params);
    
    # If @keys is not empty then we convert any named 
    # parameters that have scalar values to arrayrefs
    # that match.
    foreach my $key (@keys) {
        if (exists $params->{$key}) {
            $params->{$key} = ref $params->{$key} 
                              ? $params->{$key} 
                              : [ $params->{$key} ];
        }
    }

    return ($self, $params);
}

sub translate {
    my ($params, $mapped) = @_;
    my %changes;
    while (my ($key,$value) = each (%$params)) {
        my $new_field = $mapped->{$key} || $key;
        $changes{$new_field} = $value;
    }
    return \%changes;
}

sub params_to_objects {
    my ($params, $class) = @_;
    my (@objects, @objects_by_ids);

    @objects = map { $class->check($_) }
        @{ $params->{names} } if $params->{names};

    @objects_by_ids = map { $class->check({ id => $_ }) }
        @{ $params->{ids} } if $params->{ids};

    push(@objects, @objects_by_ids);
    my %seen;
    @objects = grep { !$seen{$_->id}++ } @objects;
    return \@objects;
}

sub fix_credentials {
    my ($params) = @_;
    # Allow user to pass in login=foo&password=bar as a convenience
    # even if not calling GET /login. We also do not delete them as
    # GET /login requires "login" and "password".
    if (exists $params->{'login'} && exists $params->{'password'}) {
        $params->{'Bugzilla_login'}    = $params->{'login'};
        $params->{'Bugzilla_password'} = $params->{'password'};
    }
    # Allow user to pass token=12345678 as a convenience which becomes
    # "Bugzilla_token" which is what the auth code looks for.
    if (exists $params->{'token'}) {
        $params->{'Bugzilla_token'} = $params->{'token'};
    }

    # Allow extensions to modify the credential data before login
    Bugzilla::Hook::process('webservice_fix_credentials', { params => $params });
}

__END__

=head1 NAME

Bugzilla::WebService::Util - Utility functions used inside of the WebService
code. These are B<not> functions that can be called via the WebService.

=head1 DESCRIPTION

This is somewhat like L<Bugzilla::Util>, but these functions are only used
internally in the WebService code.

=head1 SYNOPSIS

 filter({ include_fields => ['id', 'name'], 
          exclude_fields => ['name'] }, $hash);
 my $wants = filter_wants $params, 'field_name';
 validate(@_, 'ids');

=head1 METHODS

=head2 filter

This helps implement the C<include_fields> and C<exclude_fields> arguments
of WebService methods. Given a hash (the second argument to this subroutine),
this will remove any keys that are I<not> in C<include_fields> and then remove
any keys that I<are> in C<exclude_fields>.

An optional third option can be passed that prefixes the field name to allow
filtering of data two or more levels deep.

For example, if you want to filter out the C<id> key/value in components returned
by Product.get, you would use the value C<component.id> in your C<exclude_fields>
list.

=head2 filter_wants

Returns C<1> if a filter would preserve the specified field when passing
a hash to L</filter>, C<0> otherwise.

=head2 validate

This helps in the validation of parameters passed into the WebService
methods. Currently it converts listed parameters into an array reference
if the client only passed a single scalar value. It modifies the parameters
hash in place so other parameters should be unaltered.

=head2 params_to_objects

Creates objects of the type passed in as the second parameter, using the
parameters passed to a WebService method (the first parameter to this function).
Helps make life simpler for WebService methods that internally create objects
via both "ids" and "names" fields. Also de-duplicates objects that were loaded
by both "ids" and "names". Returns an arrayref of objects.

=head2 fix_credentials

Allows for certain parameters related to authentication such as Bugzilla_login,
Bugzilla_password, and Bugzilla_token to have shorter named equivalents passed in.
This function converts the shorter versions to their respective internal names.

=head2 extract_flags

Subroutine that takes a list of hashes that are potential flag changes for
both bugs and attachments. Then breaks the list down into two separate lists
based on if the change is to add a new flag or to update an existing flag.

=head1 B<Methods in need of POD>

=over

=item taint_data

=back
