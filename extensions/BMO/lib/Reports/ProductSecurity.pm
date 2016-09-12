# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::BMO::Reports::ProductSecurity;
use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Product;

sub report {
    my ($vars) = @_;
    my $user = Bugzilla->user;

    ($user->in_group('admin') || $user->in_group('infrasec'))
        || ThrowUserError('auth_failure', { group  => 'admin',
                                            action => 'run',
                                            object => 'product_security' });

    my $moco = Bugzilla::Group->new({ name => 'mozilla-employee-confidential' })
        or return;

    my $products = [];
    foreach my $product (@{ Bugzilla::Product->match({}) }) {
        my $default_group = $product->default_security_group_obj;
        my $group_controls = $product->group_controls();

        my $item = {
            name                    => $product->name,
            default_security_group  => $product->default_security_group,
            group_visibility        => 'None/None',
            moco                    => exists $group_controls->{$moco->id},
        };

        if ($default_group) {
            if (my $control = $group_controls->{$default_group->id}) {
                $item->{group_visibility} = control_to_string($control->{membercontrol}) .
                                            '/' . control_to_string($control->{othercontrol});
            }
        }

        $item->{group_problem} = $default_group ? '' : "Invalid group " . $product->default_security_group;
        $item->{visibility_problem} = 'Default security group should be Shown/Shown'
            if ($item->{group_visibility} ne 'Shown/Shown')
                && ($item->{group_visibility} ne 'Mandatory/Mandatory')
                && ($item->{group_visibility} ne 'Default/Default');

        push @$products, $item;
    }
    $vars->{products} = $products;
}

sub control_to_string {
    my ($control) = @_;
    return 'NA'         if $control == CONTROLMAPNA;
    return 'Shown'      if $control == CONTROLMAPSHOWN;
    return 'Default'    if $control == CONTROLMAPDEFAULT;
    return 'Mandatory'  if $control == CONTROLMAPMANDATORY;
    return '';
}

1;
