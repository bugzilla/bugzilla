/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

// Product and component search to file a new bug

$(function() {
    'use strict';

    function hideNotifications(target) {
        var id = '#' + $(target).prop('id');
        var that = $(id);
        if (that.data('counter') === 0)
            that.removeClass('autocomplete-running');
        $(id + '-no_results').hide();
        $(id + '-too_many_results').hide();
        $(id + '-error').hide();
    }

    function searchComplete(query, suggestions) {
        var that = $(this);
        var id = '#' + that.prop('id');

        that.data('counter', that.data('counter') - 1);
        hideNotifications(this);
        if (document.activeElement != this)
            that.devbridgeAutocomplete('hide');
        if (that.data('error')) {
            searchError.call(that[0], null, null, null, that.data('error'));
            that.data('error', '');
        }

        if (suggestions.length === 0) {
            $(id + '-no_results').show();
            $(document).trigger('pcs:no_results', [ that ]);
        }
        else if (suggestions.length > that.data('max_results')) {
            $(id + '-too_many_results').show();
            $(document).trigger('pcs:too_many_results', [ that ]);
        }
        else {
            $(document).trigger('pcs:results', [ that, suggestions ]);
        }
    }

    function searchError(q, jqXHR, textStatus, errorThrown) {
        var that = $(this);
        that.data('counter', that.data('counter') - 1);
        hideNotifications(this);
        if (errorThrown !== 'abort') {
            $('#' + that.attr('id') + '-error').show();
            console.log(errorThrown);
        }
    }

    $('.prod_comp_search')
        .each(function() {
            var that = $(this);
            var params = {
                limit: (that.data('max_results') + 1)
            };
            if (BUGZILLA.api_token) {
                params.Bugzilla_api_token = BUGZILLA.api_token;
            }
            that.devbridgeAutocomplete({
                serviceUrl: function(query) {
                    return 'rest/prod_comp_search/' + encodeURIComponent(query);
                },
                params: params,
                deferRequestBy: 250,
                minChars: 3,
                maxHeight: 500,
                tabDisabled: true,
                autoSelectFirst: true,
                triggerSelectOnValidInput: false,
                width: '',
                transformResult: function(response) {
                    response = $.parseJSON(response);
                    if (response.error) {
                        that.data('error', response.message);
                        return { suggestions: [] };
                    }
                    return {
                        suggestions: $.map(response.products, function(dataItem) {
                            if (dataItem.component) {
                                return {
                                    value: dataItem.product + ' :: ' + dataItem.component,
                                    data : dataItem
                                };
                            }
                            else {
                                return {
                                    value: dataItem.product,
                                    data : dataItem
                                };
                            }
                        })
                    };
                },
                formatResult: function(suggestion, currentValue) {
                    var value = (suggestion.data.component ? suggestion.data.component : suggestion.data.product);
                    var escaped = value.htmlEncode();
                    if (suggestion.data.component) {
                        return '-&nbsp;' + escaped;
                    }
                    else {
                        return '<b>' + escaped + '</b>';
                    }
                    return suggestion.data.component ? '-&nbsp;' + escaped : escaped;
                },
                beforeRender: function(container) {
                    container.css('min-width', that.outerWidth() - 2 + 'px');
                },
                onSearchStart: function(params) {
                    var that = $(this);
                    params.match = $.trim(params.match);
                    that.addClass('autocomplete-running');
                    that.data('counter', that.data('counter') + 1);
                    that.data('error', '');
                    hideNotifications(this);
                },
                onSearchComplete: searchComplete,
                onSearchError: searchError,
                onSelect: function(suggestion) {
                    var that = $(this);
                    if (that.data('ignore-select'))
                        return;

                    var params = [];
                    if (that.data('format'))
                        params.push('format=' + encodeURIComponent(that.data('format')));
                    if (that.data('cloned_bug_id'))
                        params.push('cloned_bug_id=' + encodeURIComponent(that.data('cloned_bug_id')));
                    params.push('product=' + encodeURIComponent(suggestion.data.product));
                    if (suggestion.data.component)
                        params.push('component=' + encodeURIComponent(suggestion.data.component));

                    var url = that.data('script_name') + '?' + params.join('&');
                    if (that.data('anchor_component') && suggestion.data.component)
                        url += "#" + encodeURIComponent(suggestion.data.component);
                    document.location.href = url;
                }
            });
        })
        .data('counter', 0);
});
