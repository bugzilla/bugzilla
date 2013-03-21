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
use Bugzilla::Util qw(detaint_natural trick_taint);

sub prod_comp_search {
    my ($self, $params) = @_;
    my $user = Bugzilla->user;
    my $dbh = Bugzilla->switch_to_shadow_db();

    my $search = $params->{'search'};
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

    my @list;
    foreach my $word (split(/[\s,]+/, $search)) {
        if ($word ne "") {
            my $sql_word = $dbh->quote($word);
            trick_taint($sql_word);
            # note: CONCAT_WS is MySQL specific
            my $field = "CONCAT_WS(' ', products.name, products.description,
                                   components.name, components.description)";
            push(@list, $dbh->sql_iposition($sql_word, $field) . " > 0");
        }
    }

    my $products = $dbh->selectall_arrayref("
        SELECT products.name AS product,
               components.name AS component
          FROM products
               INNER JOIN components ON products.id = components.product_id
         WHERE (" . join(" AND ", @list) . ")
               AND products.id IN (" . join(",", @$enterable_ids) . ")
      ORDER BY products.name $limit",
        { Slice => {} });

    # To help mozilla staff file bmo administration bugs into the right
    # component, sort bmo in front of bugzilla.
    if ($user->in_group('mozilla-corporation') || $user->in_group('mozilla-foundation')) {
        $products = [
            sort {
                return 1 if $a->{product} eq 'Bugzilla'
                            && $b->{product} eq 'bugzilla.mozilla.org';
                return -1 if $b->{product} eq 'Bugzilla'
                             && $a->{product} eq 'bugzilla.mozilla.org';
                return lc($a->{product}) cmp lc($b->{product})
                       || lc($a->{component}) cmp lc($b->{component});
            } @$products
        ];
    }

    return { products => $products };
}

1;
