/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    'use strict';

    var json_data = {};

    function onSelectProduct() {
        var component = $('#component');
        var product   = $('#product');

        if (product.val() == '') {
            component.empty();
            return;
        }

        if (!json_data) return;

        component.empty();
        component.append(new Option('__Any__', ''));

        var products = json_data.products;
        for (var i = 0, l = products.length; i < l; i++) {
            if (products[i].name != product.val()) continue;
            var components = products[i].components;
            for (var j = 0, k = components.length; j < k; j++) {
                var selected = !!components[j].selected;
                component.append(new Option(components[j].name,
                                            components[j].name,
                                            selected, selected));
            }
        }
    }

    $('#product').change(function() {
        onSelectProduct();
    });

    $('#triageOwners').submit(function() {
        // do not pass json_data in the params
        $('#json_data').remove();
        return true;
    });

    $(document).ready(function () {
        json_data = $('#json_data').data('json_data');
        onSelectProduct();
    });
});
