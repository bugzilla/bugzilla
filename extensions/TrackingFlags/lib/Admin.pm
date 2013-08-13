# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::TrackingFlags::Admin;

use strict;
use warnings;

use Bugzilla;
use Bugzilla::Component;
use Bugzilla::Error;
use Bugzilla::Group;
use Bugzilla::Product;
use Bugzilla::Util qw(trim detaint_natural);

use Bugzilla::Extension::TrackingFlags::Constants;
use Bugzilla::Extension::TrackingFlags::Flag;
use Bugzilla::Extension::TrackingFlags::Flag::Value;
use Bugzilla::Extension::TrackingFlags::Flag::Visibility;

use JSON;
use Scalar::Util qw(blessed);

use base qw(Exporter);
our @EXPORT = qw(
    admin_list
    admin_edit
);

#
# page loading
#

sub admin_list {
    my ($vars) = @_;

    $vars->{flags} = [ Bugzilla::Extension::TrackingFlags::Flag->get_all() ];
}

sub admin_edit {
    my ($vars, $page) = @_;
    my $input = Bugzilla->input_params;

    $vars->{groups}  = _groups_to_json();
    $vars->{mode}    = $input->{mode} || 'new';
    $vars->{flag_id} = $input->{flag_id} || 0;
    $vars->{tracking_flag_types} = FLAG_TYPES;

    if ($input->{delete}) {
        my $flag = Bugzilla::Extension::TrackingFlags::Flag->new($vars->{flag_id})
            || ThrowCodeError('tracking_flags_invalid_item_id', { item => 'flag', id => $vars->{flag_id} });
        $flag->remove_from_db();

        $vars->{message} = 'tracking_flag_deleted';
        $vars->{flag}    = $flag;
        $vars->{flags}   = [ Bugzilla::Extension::TrackingFlags::Flag->get_all() ];

        print Bugzilla->cgi->header;
        my $template = Bugzilla->template;
        $template->process('pages/tracking_flags_admin_list.html.tmpl', $vars)
            || ThrowTemplateError($template->error());
        exit;

    } elsif ($input->{save}) {
        # save

        my ($flag, $values, $visibilities) = _load_from_input($input, $vars);
        _validate($flag, $values, $visibilities);
        my $flag_obj = _update_db($flag, $values, $visibilities);

        $vars->{flag}       = $flag_obj;
        $vars->{values}     = _flag_values_to_json($values);
        $vars->{visibility} = _flag_visibility_to_json($visibilities);
        $vars->{can_delete} = !$flag_obj->has_bug_values;

        if ($vars->{mode} eq 'new') {
            $vars->{message} = 'tracking_flag_created';
        } else {
            $vars->{message} = 'tracking_flag_updated';
        }

    } else {
        # initial load

        if ($vars->{mode} eq 'edit') {
            # edit - straight load
            my $flag = Bugzilla::Extension::TrackingFlags::Flag->new($vars->{flag_id})
                || ThrowCodeError('tracking_flags_invalid_item_id', { item => 'flag', id => $vars->{flag_id} });
            $vars->{flag}       = $flag;
            $vars->{values}     = _flag_values_to_json($flag->values);
            $vars->{visibility} = _flag_visibility_to_json($flag->visibility);
            $vars->{can_delete} = !$flag->has_bug_values;

        } elsif ($vars->{mode} eq 'copy') {
            # copy - load the source flag
            $vars->{mode} = 'new';
            my $flag = Bugzilla::Extension::TrackingFlags::Flag->new($input->{copy_from})
                || ThrowCodeError('tracking_flags_invalid_item_id', { item => 'flag', id => $vars->{copy_from} });

            # increment the number at the end of the name and description
            if ($flag->name =~ /^(\D+)(\d+)$/) {
                $flag->set_name("$1" . ($2 + 1));
            }
            if ($flag->description =~ /^(\D+)(\d+)$/) {
                $flag->set_description("$1" . ($2 + 1));
            }
            $flag->set_sortkey(_next_unique_sortkey($flag->sortkey));
            $flag->set_type($flag->flag_type);
            # always default new flags as active, even when copying an inactive one
            $flag->set_is_active(1);

            $vars->{flag}       = $flag;
            $vars->{values}     = _flag_values_to_json($flag->values, 1);
            $vars->{visibility} = _flag_visibility_to_json($flag->visibility, 1);
            $vars->{can_delete} = 0;

        } else {
            $vars->{mode} = 'new';
            $vars->{flag} = {
                sortkey    => 0,
                is_active  => 1,
            };
            $vars->{values} = _flag_values_to_json([
                {
                    id              => 0,
                    value           => '---',
                    setter_group_id => '',
                    is_active       => 1,
                },
            ]);
            $vars->{visibility} = '';
            $vars->{can_delete} = 0;
        }
    }
}

sub _load_from_input {
    my ($input, $vars) = @_;

    # flag

    my $flag = {
        id          => $input->{flag_id}   || 0,
        name        => trim($input->{flag_name} || ''),
        description => trim($input->{flag_desc} || ''),
        sortkey     => $input->{flag_sort} || 0,
        type        => trim($input->{flag_type} || ''),
        is_active   => $input->{flag_active} ? 1 : 0,
    };
    detaint_natural($flag->{id});
    detaint_natural($flag->{sortkey});
    detaint_natural($flag->{is_active});

    # values

    my $values = decode_json($input->{values} || '[]');
    foreach my $value (@$values) {
        $value->{value}           = '' unless exists $value->{value} && defined $value->{value};
        $value->{setter_group_id} = '' unless $value->{setter_group_id};
        $value->{is_active}       = $value->{is_active} ? 1 : 0;
    }

    # vibility

    my $visibilities = decode_json($input->{visibility} || '[]');
    foreach my $visibility (@$visibilities) {
        $visibility->{product}   = '' unless exists $visibility->{product} && defined $visibility->{product};
        $visibility->{component} = '' unless exists $visibility->{component} && defined $visibility->{component};
    }

    return ($flag, $values, $visibilities);
}

sub _next_unique_sortkey {
    my ($sortkey) = @_;

    my %current;
    foreach my $flag (Bugzilla::Extension::TrackingFlags::Flag->get_all()) {
        $current{$flag->sortkey} = 1;
    }

    $sortkey += 5;
    $sortkey += 5 while exists $current{$sortkey};
    return $sortkey;
}

#
# validation
#

sub _validate {
    my ($flag, $values, $visibilities) = @_;

    # flag

    my @missing;
    push @missing, 'Field Name'        if $flag->{name} eq '';
    push @missing, 'Field Description' if $flag->{description} eq '';
    push @missing, 'Field Sort Key'    if $flag->{sortkey} eq '';
    scalar(@missing)
        && ThrowUserError('tracking_flags_missing_mandatory', { fields => \@missing });

    $flag->{name} =~ /^cf_/
        || ThrowUserError('tracking_flags_cf_prefix');

    if ($flag->{id}) {
        my $old_flag = Bugzilla::Extension::TrackingFlags::Flag->new($flag->{id})
            || ThrowCodeError('tracking_flags_invalid_item_id', { item => 'flag', id => $flag->{id} });
        if ($flag->{name} ne $old_flag->name) {
            Bugzilla::Field->new({ name => $flag->{name} })
                && ThrowUserError('field_already_exists', { field => { name => $flag->{name} }});
        }
    } else {
        Bugzilla::Field->new({ name => $flag->{name} })
            && ThrowUserError('field_already_exists', { field => { name => $flag->{name} }});
    }

    # values

    scalar(@$values)
        || ThrowUserError('tracking_flags_missing_values');

    my %seen;
    foreach my $value (@$values) {
        my $v = $value->{value};

        $v eq ''
            && ThrowUserError('tracking_flags_missing_value');

        exists $seen{$v}
            && ThrowUserError('tracking_flags_duplicate_value', { value => $v });
        $seen{$v} = 1;

        push @missing, "Setter for $v" if !$value->{setter_group_id};
    }
    scalar(@missing)
        && ThrowUserError('tracking_flags_missing_mandatory', { fields => \@missing });

    # visibility

    scalar(@$visibilities)
        || ThrowUserError('tracking_flags_missing_visibility');

    %seen = ();
    foreach my $visibility (@$visibilities) {
        my $name = $visibility->{product} . ':' . $visibility->{component};

        exists $seen{$name}
            && ThrowUserError('tracking_flags_duplicate_visibility', { name => $name });

        $visibility->{product_obj} = Bugzilla::Product->new({ name => $visibility->{product} })
            || ThrowCodeError('tracking_flags_invalid_product', { product => $visibility->{product} });

        if ($visibility->{component} ne '') {
            $visibility->{component_obj} = Bugzilla::Component->new({ product => $visibility->{product_obj},
                                                                      name    => $visibility->{component} })
                || ThrowCodeError('tracking_flags_invalid_component', { component => $visibility->{component} });
        }
    }

}

#
# database updating
#

sub _update_db {
    my ($flag, $values, $visibilities) = @_;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();
    my $flag_obj = _update_db_flag($flag);
    _update_db_values($flag_obj, $flag, $values);
    _update_db_visibility($flag_obj, $flag, $visibilities);
    $dbh->bz_commit_transaction();

    return $flag_obj;
}

sub _update_db_flag {
    my ($flag) = @_;

    my $object_set = {
        name        => $flag->{name},
        description => $flag->{description},
        sortkey     => $flag->{sortkey},
        type        => $flag->{type},
        is_active   => $flag->{is_active},
    };

    my $flag_obj;
    if ($flag->{id}) {
        # update existing flag
        $flag_obj = Bugzilla::Extension::TrackingFlags::Flag->new($flag->{id})
            || ThrowCodeError('tracking_flags_invalid_item_id', { item => 'flag', id => $flag->{id} });
        $flag_obj->set_all($object_set);
        $flag_obj->update();

    } else {
        # create new flag
        $flag_obj = Bugzilla::Extension::TrackingFlags::Flag->create($object_set);
    }

    return $flag_obj;
}

sub _update_db_values {
    my ($flag_obj, $flag, $values) = @_;

    # delete
    foreach my $current_value (@{ $flag_obj->values }) {
        if (!grep { $_->{id} == $current_value->id } @$values) {
            $current_value->remove_from_db();
        }
    }

    # add/update
    my $sortkey = 0;
    foreach my $value (@{ $values }) {
        $sortkey += 10;

        my $object_set = {
            value           => $value->{value},
            setter_group_id => $value->{setter_group_id},
            is_active       => $value->{is_active},
            sortkey         => $sortkey,
        };

        if ($value->{id}) {
            my $value_obj = Bugzilla::Extension::TrackingFlags::Flag::Value->new($value->{id})
                || ThrowCodeError('tracking_flags_invalid_item_id', { item => 'flag value', id => $flag->{id} });
            $value_obj->set_all($object_set);
            $value_obj->update();
        } else {
            $object_set->{tracking_flag_id} = $flag_obj->flag_id;
            Bugzilla::Extension::TrackingFlags::Flag::Value->create($object_set);
        }
    }
}

sub _update_db_visibility {
    my ($flag_obj, $flag, $visibilities) = @_;

    # delete
    foreach my $current_visibility (@{ $flag_obj->visibility }) {
        if (!grep { $_->{id} == $current_visibility->id } @$visibilities) {
            $current_visibility->remove_from_db();
        }
    }

    # add
    foreach my $visibility (@{ $visibilities }) {
        next if $visibility->{id};
        Bugzilla::Extension::TrackingFlags::Flag::Visibility->create({
            tracking_flag_id => $flag_obj->flag_id,
            product_id       => $visibility->{product_obj}->id,
            component_id     => $visibility->{component} ? $visibility->{component_obj}->id : undef,
        });
    }
}

#
# serialisation
#

sub _groups_to_json {
    my @data;
    foreach my $group (sort { $a->name cmp $b->name } Bugzilla::Group->get_all()) {
        push @data, {
            id   => $group->id,
            name => $group->name,
        };
    }
    return encode_json(\@data);
}

sub _flag_values_to_json {
    my ($values, $is_copy) = @_;
    # setting is_copy will set the id's to zero, to force new values rather
    # than editing existing ones
    my @data;
    foreach my $value (@$values) {
        push @data, {
            id              => $is_copy ? 0 : $value->{id},
            value           => $value->{value},
            setter_group_id => $value->{setter_group_id},
            is_active       => $value->{is_active} ? JSON::true : JSON::false,
        };
    }
    return encode_json(\@data);
}

sub _flag_visibility_to_json {
    my ($visibilities, $is_copy) = @_;
    # setting is_copy will set the id's to zero, to force new visibilites
    # rather than editing existing ones
    my @data;

    foreach my $visibility (@$visibilities) {
        my $product = exists $visibility->{product_id}
            ? $visibility->product->name
            : $visibility->{product};
        my $component;
        if (exists $visibility->{component_id} && $visibility->{component_id}) {
            $component = $visibility->component->name;
        } elsif (exists $visibility->{component}) {
            $component = $visibility->{component};
        } else {
            $component = undef;
        }
        push @data, {
            id        => $is_copy ? 0 : $visibility->{id},
            product   => $product,
            component => $component,
        };
    }
    @data = sort {
                lc($a->{product}) cmp lc($b->{product})
                || lc($a->{component}) cmp lc($b->{component})
            } @data;
    return encode_json(\@data);
}

1;
