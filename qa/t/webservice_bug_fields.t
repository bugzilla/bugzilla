# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Data::Dumper;
use Test::More;
use List::Util qw(first);
use QA::Util;

my ($config, @clients) = get_rpc_clients();
plan tests => ($config->{test_extensions} ? 1338 : 1320);

use constant INVALID_FIELD_NAME => 'invalid_field';
use constant INVALID_FIELD_ID => -1;
sub GLOBAL_GENERAL_FIELDS {
    my @fields = qw(
        attach_data.thedata
        attachments.description
        attachments.filename
        attachments.isobsolete
        attachments.ispatch
        attachments.isprivate
        attachments.mimetype
        attachments.submitter

        flagtypes.name
        requestees.login_name
        setters.login_name

        alias
        assigned_to
        blocked
        bug_file_loc
        bug_group
        bug_id
        cc
        cclist_accessible
        classification
        commenter
        content
        creation_ts
        days_elapsed
        delta_ts
        dependson
        everconfirmed
        keywords
        longdesc
        longdescs.isprivate
        owner_idle_time
        product
        qa_contact
        reporter
        reporter_accessible
        see_also
        short_desc
        status_whiteboard

        deadline
        estimated_time
        percentage_complete
        remaining_time
        work_time
    );
    push(@fields, 'votes') if QA::Util::get_config()->{test_extensions};

    return @fields;
}

use constant STANDARD_SELECT_FIELDS =>
    qw(bug_severity bug_status op_sys priority rep_platform resolution);

use constant ALL_SELECT_FIELDS => (STANDARD_SELECT_FIELDS,
    qw(cf_qa_status cf_single_select));
use constant PRODUCT_FIELDS => qw(version target_milestone component);
use constant ALL_FIELDS => (GLOBAL_GENERAL_FIELDS, ALL_SELECT_FIELDS,
                            PRODUCT_FIELDS);
use constant MANDATORY_FIELDS => qw(short_desc product version component);

use constant PUBLIC_PRODUCT  => 'Another Product';
use constant PRIVATE_PRODUCT => 'QA-Selenium-TEST';

sub get_field {
    my ($fields, $field) = @_;
    return first { $_->{name} eq $field } @$fields;
}

sub get_products_from_field {
    my $field = shift;
    my %products;
    foreach my $value (@{ $field->{values} }) {
        foreach my $vis_value (@{ $value->{visibility_values} }) {
            $products{$vis_value} = 1;
        }
    }
    return \%products;
}

our %field_ids;
foreach my $rpc (@clients) {
    my $call = $rpc->bz_call_success('Bug.fields');
    my $fields = $call->result->{fields};
    foreach my $field (ALL_FIELDS) {
        my $field_data = get_field($fields, $field);
        ok($field_data, "$field is in the returned result")
            or diag(Dumper($fields));
        $field_ids{$field} = $field_data->{id};

        if (grep($_ eq $field, MANDATORY_FIELDS)) {
            ok($field_data->{is_mandatory}, "$field is mandatory");
        }
        else {
            ok(!$field_data->{is_mandatory}, "$field is not mandatory");
        }
    }

    foreach my $field (ALL_SELECT_FIELDS, PRODUCT_FIELDS) {
        my $field_data = get_field($fields, $field);
        ok(defined $field_data->{visibility_values},
           "$field has visibility_values defined");
        my $field_vis_undefs = grep { !defined $_ }
                                    @{ $field_data->{visibility_values} };
        is($field_vis_undefs, 0, "$field.visibility_values has no undefs")
          or diag(Dumper($field_data->{visibility_values}));

        ok(defined $field_data->{values},
           "$field has 'values' defined");
        my $num_values = scalar @{ $field_data->{values} };
        ok($num_values, "$field has $num_values values");
        # The first bug status is a fake one and has no name, so we choose the 2nd item.
        my $first_value = $field_data->{values}->[1];
        ok(defined $first_value->{name}, 'The first value has a name')
            or diag(Dumper($field_data->{values}));
        # The sortkey for milestones can be negative.
        cmp_ok($first_value->{sortkey}, '=~', qr/^-?\d+$/,
               "The first value has a numeric sortkey");

        ok(defined $first_value->{visibility_values},
           "$field has visibilty_values defined on its first value")
            or diag(Dumper($field_data->{values}));
        my @value_visibility_values = map { @{ $_->{visibility_values} } }
                                      @{ $field_data->{values} };
        my $undefs = grep { !defined $_ } @value_visibility_values;
        is($undefs, 0,
           "$field.values.visibility_values has no undefs");
    }

    foreach my $field (PRODUCT_FIELDS) {
        my $field_data = get_field($fields, $field);
        is($field_data->{value_field}, 'product',
           "The value_field for $field is 'product'");
        my $products = get_products_from_field($field_data);
        ok($products->{+PUBLIC_PRODUCT},
           "$field values are returned for the public product");
        ok(!$products->{+PRIVATE_PRODUCT},
           "No $field values are returned for the private product");
    }
}

my @all_tests = (
    { args => { ids   => [values %field_ids],
                names => [ALL_FIELDS] },
                test => 'Getting all fields by name and id simultaneously',
                count => scalar ALL_FIELDS
    },
    { args  => { names => [INVALID_FIELD_NAME] },
      error => "There is no field named",
      test  => 'Invalid field name'
    },
    { args  => { ids => [INVALID_FIELD_ID] },
      error => 'must be numeric',
      test  => 'Invalid field id'
    },
    { user  => 'QA_Selenium_TEST',
      args  => { names => [PRODUCT_FIELDS] },
      test  => 'Getting product-specific fields as a privileged user',
      count => scalar PRODUCT_FIELDS,
      product_private_values => 1
    },
);

foreach my $field (ALL_FIELDS) {
    push(@all_tests,
         { args => { names => [$field] },
           test => "Logged-out users can get the $field field by name" });
    push(@all_tests,
         { args => { ids => [$field_ids{$field}] },
           test => "Logged-out users can get the $field by id" });
}

sub post_success {
    my ($call, $t) = @_;
    my $fields = $call->result->{fields};
    my $count = $t->{count};
    $count = 1 if !defined $count;
    is(scalar @$fields, $count, "Exactly $count field(s) returned");

    if ($t->{product_private_values}) {
        foreach my $field (@$fields) {
            my $name = $field->{name};
            my $field_data = get_field($fields, $name);
            my $products = get_products_from_field($field_data);
            ok($products->{+PUBLIC_PRODUCT},
               "$name values are returned for the public product");
            ok($products->{+PRIVATE_PRODUCT},
               "$name values are returned for the private product");
        }
    }
}

foreach my $rpc (@clients) {
    $rpc->bz_run_tests(tests => \@all_tests,  method => 'Bug.fields',
                       post_success => \&post_success);
}
