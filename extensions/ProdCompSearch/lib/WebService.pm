# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::ProdCompSearch::WebService;

use strict;
use warnings;

use base qw(Bugzilla::WebService);

use Bugzilla::Error;
use Bugzilla::Util qw(detaint_natural trick_taint trim);

sub prod_comp_search {
    my ($self, $params) = @_;
    my $user = Bugzilla->user;
    my $dbh = Bugzilla->switch_to_shadow_db();

    my $search = trim($params->{'search'} || '');
    $search || ThrowCodeError('param_required',
        { function => 'PCS.prod_comp_search', param => 'search' });

    my $limit = detaint_natural($params->{'limit'})
                ? $dbh->sql_limit($params->{'limit'})
                : '';

    # We do this in the DB directly as we want it to be fast and
    # not have the overhead of loading full product objects

    # All products which the user has "Entry" access to.
    my $enterable_ids = $dbh->selectcol_arrayref(
           'SELECT products.id FROM products
         LEFT JOIN group_control_map
                   ON group_control_map.product_id = products.id
                      AND group_control_map.entry != 0
                      AND group_id NOT IN (' . $user->groups_as_string . ')
            WHERE group_id IS NULL
                  AND products.isactive = 1');

    if (scalar @$enterable_ids) {
        # And all of these products must have at least one component
        # and one version.
        $enterable_ids = $dbh->selectcol_arrayref(
            'SELECT DISTINCT products.id FROM products
              WHERE ' . $dbh->sql_in('products.id', $enterable_ids) .
              ' AND products.id IN (SELECT DISTINCT components.product_id
                                      FROM components
                                     WHERE components.isactive = 1)
                AND products.id IN (SELECT DISTINCT versions.product_id
                                      FROM versions
                                     WHERE versions.isactive = 1)');
    }

    return { products => [] } if !scalar @$enterable_ids;

    trick_taint($search);
    my @terms;
    my @order;

    if ($search =~ /^(.*?)::(.*)$/) {
        my ($product, $component) = (trim($1), trim($2));
        push @terms, _build_terms($product, 1, 0);
        push @terms, _build_terms($component, 0, 1);
        push @order, "products.name != " . $dbh->quote($product) if $product ne '';
        push @order, "components.name != " . $dbh->quote($component) if $component ne '';
        push @order, "products.name";
        push @order, "components.name";
    } else {
        push @terms, _build_terms($search, 1, 1);
        push @order, "products.name != " . $dbh->quote($search);
        push @order, "components.name != " . $dbh->quote($search);
        push @order, "products.name";
        push @order, "components.name";
    }
    return { products => [] } if !scalar @terms;

    # To help mozilla staff file bmo administration bugs into the right
    # component, sort bmo first when searching for 'bugzilla'
    if ($search =~ /bugzilla/i && $search !~ /^bugzilla\s*::/i
        && ($user->in_group('mozilla-corporation') || $user->in_group('mozilla-foundation')))
    {
        unshift @order, "products.name != 'bugzilla.mozilla.org'";
    }

    my $products = $dbh->selectall_arrayref("
        SELECT products.name AS product,
               components.name AS component
          FROM products
               INNER JOIN components ON products.id = components.product_id
         WHERE (" . join(" AND ", @terms) . ")
               AND products.id IN (" . join(",", @$enterable_ids) . ")
      ORDER BY " . join(", ", @order) . " $limit",
        { Slice => {} });

    return { products => $products };
}

sub _build_terms {
    my ($query, $product, $component) = @_;
    my $dbh = Bugzilla->dbh();

    my @fields;
    push @fields, 'products.name', 'products.description' if $product;
    push @fields, 'components.name', 'components.description' if $component;
    # note: CONCAT_WS is MySQL specific
    my $field = "CONCAT_WS(' ', ". join(',', @fields) . ")";

    my @terms;
    foreach my $word (split(/[\s,]+/, $query)) {
        push(@terms, $dbh->sql_iposition($dbh->quote($word), $field) . " > 0")
            if $word ne '';
    }
    return @terms;
}

1;
