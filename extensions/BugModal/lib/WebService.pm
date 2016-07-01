# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugModal::WebService;
use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Group;
use Bugzilla::Keyword;
use Bugzilla::Milestone;
use Bugzilla::Product;
use Bugzilla::Version;
use List::MoreUtils qw(any first_value);

# these methods are much lighter than our public API calls

sub rest_resources {
    return [
        # return all the lazy-loaded data; kept in sync with the UI's
        # requirements.
        qr{^/bug_modal/edit/(\d+)$}, {
            GET => {
                method => 'edit',
                params => sub {
                    return { id => $_[0] }
                },
            },
        },

        # returns pre-formatted html, enabling reuse of the user template
        qr{^/bug_modal/cc/(\d+)$}, {
            GET => {
                method => 'cc',
                params => sub {
                    return { id => $_[0] }
                },
            },
        },

        # returns fields that require touching when the product is changed
        qw{^/bug_modal/new_product/(\d+)$}, {
            GET => {
                method => 'new_product',
                params => sub {
                    # products with slashes in their name means we have to grab
                    # the product from the query-string instead of the path
                    return { id => $_[0], product_name => Bugzilla->input_params->{product} }
                },
            },
        },
    ]
}

# everything we need for edit mode in a single call, returning just the fields
# that the ui requires.
sub edit {
    my ($self, $params) = @_;
    my $user = Bugzilla->user;
    my $bug = Bugzilla::Bug->check({ id => $params->{id} });

    # the keys of the options hash must match the field id in the ui
    my %options;

    my @products = @{ $user->get_enterable_products };
    unless (grep { $_->id == $bug->product_id } @products) {
        unshift @products, $bug->product_obj;
    }
    $options{product} = [ map { { name => $_->name } } @products ];

    $options{component}         = _name($bug->product_obj->components, $bug->component);
    $options{version}           = _name($bug->product_obj->versions, $bug->version);
    $options{target_milestone}  = _name($bug->product_obj->milestones, $bug->target_milestone);
    $options{priority}          = _name('priority', $bug->priority);
    $options{bug_severity}      = _name('bug_severity', $bug->bug_severity);
    $options{rep_platform}      = _name('rep_platform', $bug->rep_platform);
    $options{op_sys}            = _name('op_sys', $bug->op_sys);

    # custom select fields
    my @custom_fields =
        grep { $_->type == FIELD_TYPE_SINGLE_SELECT || $_->type == FIELD_TYPE_MULTI_SELECT }
        Bugzilla->active_custom_fields({ product => $bug->product_obj, component => $bug->component_obj });
    foreach my $field (@custom_fields) {
        my $field_name = $field->name;
        my @values = map { { name => $_->name } }
                     grep { $bug->$field_name eq $_->name
                            || ($_->is_active
                                && $bug->check_can_change_field($field_name, $bug->$field_name, $_->name)) }
                     @{ $field->legal_values };
        $options{$field_name} = \@values;
    }

    # keywords
    my @keywords = grep { $_->is_active } Bugzilla::Keyword->get_all();

    # results
    return {
        options     => \%options,
        keywords    => [ map { $_->name } @keywords ],
    };
}

sub _name {
    my ($values, $current) = @_;
    # values can either be an array-ref of values, or a field name, which
    # result in that field's legal-values being used.
    if (!ref($values)) {
        $values = Bugzilla::Field->new({ name => $values, cache => 1 })->legal_values;
    }
    return [
        map { { name => $_->name } }
        grep { (defined $current && $_->name eq $current) || $_->is_active }
        @$values
    ];
}

sub cc {
    my ($self, $params) = @_;
    my $template = Bugzilla->template;
    my $bug = Bugzilla::Bug->check({ id => $params->{id} });
    my $vars = {
        bug     => $bug,
        cc_list => [
            sort { lc($a->identity) cmp lc($b->identity) }
            @{ $bug->cc_users }
        ]
    };

    my $html = '';
    $template->process('bug_modal/cc_list.html.tmpl', $vars, \$html)
        || ThrowTemplateError($template->error);
    return { html => $html };
}

sub new_product {
    my ($self, $params) = @_;
    my $dbh     = Bugzilla->dbh;
    my $user    = Bugzilla->user;
    my $bug     = Bugzilla::Bug->check({ id => $params->{id} });
    my $product = Bugzilla::Product->check({ name => $params->{product_name}, cache => 1 });
    my $true    = $self->type('boolean', 1);
    my %result;

    # components

    my $components = _name($product->components);
    my $current_component = $bug->component;
    if (my $component = first_value { $_->{name} eq $current_component} @$components) {
        # identical component in both products
        $component->{selected} = $true;
    }
    else {
        # default to a blank value
        unshift @$components, {
            name     => '',
            selected => $true,
        };
    }
    $result{component} = $components;

    # milestones

    my $milestones = _name($product->milestones);
    my $current_milestone = $bug->target_milestone;
    if ($bug->check_can_change_field('target_milestone', 0, 1)
        && (my $milestone = first_value { $_->{name} eq $current_milestone} @$milestones))
    {
        # identical milestone in both products
        $milestone->{selected} = $true;
    }
    else {
        # use default milestone
        my $default_milestone = $product->default_milestone;
        my $milestone = first_value { $_->{name} eq $default_milestone } @$milestones;
        $milestone->{selected} = $true;
    }
    $result{target_milestone} = $milestones;

    # versions

    my $versions = _name($product->versions);
    my $current_version = $bug->version;
    my $selected_version;
    if (my $version = first_value { $_->{name} eq $current_version } @$versions) {
        # identical version in both products
        $version->{selected} = $true;
        $selected_version = $version;
    }
    elsif (
        $current_version =~ /^(\d+) Branch$/
        || $current_version =~ /^Firefox (\d+)$/
        || $current_version =~ /^(\d+)$/)
    {
        # firefox, with its three version naming schemes
        my $branch = $1;
        foreach my $test_version ("$branch Branch", "Firefox $branch", $branch) {
            if (my $version = first_value { $_->{name} eq $test_version } @$versions) {
                $version->{selected} = $true;
                $selected_version = $version;
                last;
            }
        }
    }
    if (!$selected_version) {
        # "unspecified", "other"
        foreach my $test_version ("unspecified", "other") {
            if (my $version = first_value { lc($_->{name}) eq $test_version } @$versions) {
                $version->{selected} = $true;
                $selected_version = $version;
                last;
            }
        }
    }
    if (!$selected_version) {
        # default to a blank value
        unshift @$versions, {
            name     => '',
            selected => $true,
        };
    }
    $result{version} = $versions;

    # groups

    my @groups;

    # find invalid groups
    push @groups,
        map {{
            type    => 'invalid',
            group   => $_,
            checked => 0,
        }}
        @{ Bugzilla::Bug->get_invalid_groups({ bug_ids => [ $bug->id ], product => $product }) };

    # logic lifted from bug/process/verify-new-product.html.tmpl
    my $current_groups = $bug->groups_in;
    my $group_controls = $product->group_controls;
    foreach my $group_id (keys %$group_controls) {
        my $group_control = $group_controls->{$group_id};
        if ($group_control->{membercontrol} == CONTROLMAPMANDATORY
            || ($group_control->{othercontrol} == CONTROLMAPMANDATORY && !$user->in_group($group_control->{name})))
        {
            # mandatory, always checked
            push @groups, {
                type    => 'mandatory',
                group   => $group_control->{group},
                checked => 1,
            };
        }
        elsif (
            ($group_control->{membercontrol} != CONTROLMAPNA && $user->in_group($group_control->{name}))
            || $group_control->{othercontrol} != CONTROLMAPNA)
        {
            # optional, checked if..
            my $group = $group_control->{group};
            my $checked =
                # same group as current product
                (any { $_->id == $group->id } @$current_groups)
                # member default
                || $group_control->{membercontrol} == CONTROLMAPDEFAULT && $user->in_group($group_control->{name})
                # or other default
                || $group_control->{othercontrol} == CONTROLMAPDEFAULT && !$user->in_group($group_control->{name})
            ;
            push @groups, {
                type    => 'optional',
                group   => $group_control->{group},
                checked => $checked || 0,
            };
        }
    }

    my $default_group_name = $product->default_security_group;
    if (my $default_group = first_value { $_->{group}->name eq $default_group_name } @groups) {
        # because we always allow the default product group to be selected, it's never invalid
        $default_group->{type} = 'optional' if $default_group->{type} eq 'invalid';
    }
    else {
        # add the product's default group if it's missing
        unshift @groups, {
            type    => 'optional',
            group   => $product->default_security_group_obj,
            checked => 0,
        };
    }

    # if the bug is currently in a group, ensure a group is checked by default
    # by checking the product's default group if no other groups apply
    if (@$current_groups && !any { $_->{checked} } @groups) {
        foreach my $g (@groups) {
            next unless $g->{group}->name eq $default_group_name;
            $g->{checked} = 1;
            last;
        }
    }

    # group by type and flatten
    my $vars = {
        product => $product,
        groups  => { invalid => [], mandatory => [], optional => [] },
    };
    foreach my $g (@groups) {
        push @{ $vars->{groups}->{$g->{type}} }, {
            id          => $g->{group}->id,
            name        => $g->{group}->name,
            description => $g->{group}->description,
            checked     => $g->{checked},
        };
    }

    # build group selection html
    my $template = Bugzilla->template;
    $template->process('bug_modal/new_product_groups.html.tmpl', $vars, \$result{groups})
        || ThrowTemplateError($template->error);

    return \%result;
}

1;
