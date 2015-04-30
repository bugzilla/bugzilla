/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

// Product and component search to file a new bug

$(function() {
    'use strict';
    $('.prod_comp_search').autocomplete({
        minLength: 3,
        delay: 500,
        source: function(request, response) {
            var el = this.element;
            $(document).trigger('pcs:search', [ el ]);
            var id = '#' + el.prop('id');
            var throbber = $('#' + $(el).data('throbber'));
            throbber.show();
            $(id + '-no_components').hide();
            $(id + '-too_many_components').hide();
            $(id + '-error').hide();
            var url = 'rest/prod_comp_search/' + encodeURIComponent(request.term) +
                     '?limit=' + (el.data('max_results') + 1);
            if (BUGZILLA.api_token) {
                url += '&Bugzilla_api_token=' + encodeURIComponent(BUGZILLA.api_token);
            }
            $.ajax({
                url: url,
                contentType: 'application/json'
            })
            .done(function(data) {
                throbber.hide();
                if (data.error) {
                    $(id + '-error').show();
                    console.log(data.message);
                    return false;
                }
                if (data.products.length === 0) {
                    $(id + '-no_results').show();
                    $(document).trigger('pcs:no_results', [ el ]);
                }
                else if (data.products.length > el.data('max_results')) {
                    $(id + '-too_many_results').show();
                    $(document).trigger('pcs:too_many_results', [ el ]);
                }
                else {
                    $(document).trigger('pcs:results', [ el, data ]);
                }
                var current_product = "";
                var prod_comp_array = [];
                var base_params = [];
                if (el.data('format')) {
                    base_params.push('format=' + encodeURIComponent(el.data('format')));
                }
                if (el.data('cloned_bug_id')) {
                    base_params.push('cloned_bug_id=' + encodeURIComponent(el.data('cloned_bug_id')));
                }
                $.each(data.products, function() {
                    var params = base_params.slice();
                    params.push('product=' + encodeURIComponent(this.product));
                    if (this.product != current_product) {
                        prod_comp_array.push({
                            label:   this.product,
                            product: this.product,
                            url:     el.data('script_name') + '?' + params.join('&')
                        });
                        current_product = this.product;
                    }
                    params.push('component=' + encodeURIComponent(this.component));
                    var url = el.data('script_name') + '?' + params.join('&');
                    if (el.data('anchor_component')) {
                        url += "#" + encodeURIComponent(this.component);
                    }
                    prod_comp_array.push({
                        label:     this.product + ' :: ' + this.component,
                        product:   this.product,
                        component: this.component,
                        url:       url
                    });
                });
                response(prod_comp_array);
            })
            .fail(function(xhr, error_text) {
                if (xhr.responseJSON && xhr.responseJSON.error) {
                    error_text = xhr.responseJSON.message;
                }
                throbber.hide();
                $(id + '-comp_error').show();
                $(document).trigger('pcs:error', [ el, error_text ]);
                console.log(error_text);
            });
        },
        focus: function(event, ui) {
            event.preventDefault();
        },
        select: function(event, ui) {
            event.preventDefault();
            var el = $(this);
            el.val(ui.item.label);
            if (el.data('ignore-select')) {
                return;
            }
            if (el.data('new_tab')) {
                window.open(ui.item.url, '_blank');
            }
            else {
                window.location.href = ui.item.url;
            }
        }
    })
    .focus(function(event) {
        var el = $(event.target);
        if (el.val().length >= el.autocomplete('option', 'minLength')) {
            el.autocomplete('search');
        }
    });
    $('.prod_comp_search:focus').select();
});
