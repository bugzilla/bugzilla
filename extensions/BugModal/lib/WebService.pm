# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BugModal::WebService;
use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Field;
use Bugzilla::Keyword;
use Bugzilla::Milestone;
use Bugzilla::Version;

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
    $options{product} = [ map { { name => $_->name, description => $_->description } } @products ];

    $options{component}         = _name_desc($bug->component, $bug->product_obj->components);
    $options{version}           = _name($bug->version, $bug->product_obj->versions);
    $options{target_milestone}  = _name($bug->target_milestone, $bug->product_obj->milestones);
    $options{priority}          = _name($bug->priority, 'priority');
    $options{bug_severity}      = _name($bug->bug_severity, 'bug_severity');
    $options{rep_platform}      = _name($bug->rep_platform, 'rep_platform');
    $options{op_sys}            = _name($bug->op_sys, 'op_sys');

    # custom select fields
    my @custom_fields =
        grep { $_->type == FIELD_TYPE_SINGLE_SELECT || $_->type == FIELD_TYPE_MULTI_SELECT }
        Bugzilla->active_custom_fields({ product => $bug->product_obj, component => $bug->component_obj });
    foreach my $field (@custom_fields) {
        my $field_name = $field->name;
        $options{$field_name} = [
            map { { name => $_->name } }
            grep { $bug->$field_name eq $_->name || $_->is_active }
            @{ $field->legal_values }
        ];
    }

    # keywords
    my @keywords = Bugzilla::Keyword->get_all();

    # results
    return {
        options     => \%options,
        keywords    => [ map { $_->name } @keywords ],
    };
}

sub _name {
    my ($current, $values) = @_;
    # values can either be an array-ref of values, or a field name, which
    # result in that field's legal-values being used.
    if (!ref($values)) {
        $values = Bugzilla::Field->new({ name => $values, cache => 1 })->legal_values;
    }
    return [
        map { { name => $_->name } }
        grep { $_->name eq $current || $_->is_active }
        @$values
    ];
}

sub _name_desc {
    my ($current, $values) = @_;
    if (!ref($values)) {
        $values = Bugzilla::Field->new({ name => $values, cache => 1 })->legal_values;
    }
    return [
        map { { name => $_->name, description => $_->description } }
        grep { $_->name eq $current || $_->is_active }
        @$values
    ];
}

sub cc {
    my ($self, $params) = @_;
    my $template = Bugzilla->template;
    my $bug = Bugzilla::Bug->check({ id => $params->{id} });
    my $vars = {
        cc_list => [
            sort { lc($a->moz_nick) cmp lc($b->moz_nick) }
            @{ $bug->cc_users }
        ]
    };

    my $html = '';
    $template->process('bug_modal/cc_list.html.tmpl', $vars, \$html)
        || ThrowTemplateError($template->error);
    return { html => $html };
}

1;
