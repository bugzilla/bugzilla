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
                appendTo: $('#main-inner'),
                forceFixPosition: true,
                serviceUrl: function(query) {
                    return `${BUGZILLA.config.basepath}rest/prod_comp_search/find/${encodeURIComponent(query)}`;
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

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Show the current user's most-used components on the New Bug page.
 */
Bugzilla.FrequentComponents = class FrequentComponents {
  /**
   * Initialize a new FrequentComponents instance.
   */
  constructor() {
    this.$container = document.querySelector('#frequent-components');

    if (this.$container && BUGZILLA.user.login) {
      this.init();
    }
  }

  /**
   * Initialize the UI.
   */
  async init() {
    this.$results = this.$container.querySelector('.results');
    this.$message = this.$results.appendChild(document.createElement('p'));
    this.$message.textContent = 'Loading...';
    this.$results.setAttribute('aria-busy', 'true');
    this.$container.hidden = false;

    // Get the current params that may contain `cloned_bug_id` and `format`
    const current_params = new URLSearchParams(location.search);

    try {
      const links = (await this.fetch()).map(({ product, component }) => {
        const params = new URLSearchParams(current_params);

        params.append('product', product);
        params.append('component', component);

        return {
          href: `${BUGZILLA.config.basepath}enter_bug.cgi?${params.toString()}`,
          text: `${product} :: ${component}`,
        };
      });

      this.$message.remove();
      this.$results.insertAdjacentHTML('beforeend',
        `<ul>${links.map(({ href, text }) =>
          `<li><a href="${href.htmlEncode()}">${text.htmlEncode()}</a></li>`
        ).join('')}</ul>`
      );
    } catch (error) {
      this.$message.textContent = error.message || 'Your frequent components could not be retrieved.';
    }

    this.$results.removeAttribute('aria-busy');
  }

  /**
   * Retrieve frequently used components.
   * @returns {Promise} Results or error.
   */
  async fetch() {
    return new Promise((resolve, reject) => bugzilla_ajax({
      url: `${BUGZILLA.config.basepath}rest/prod_comp_search/frequent`
    }, ({ results }) => {
      if (!results) {
        reject(new Error('Your frequent components could not be retrieved.'));
      } else if (!results.length) {
        reject(new Error(('Your frequent components could not be found.')));
      } else {
        resolve(results);
      }
    }, () => {
      reject(new Error('Your frequent components could not be retrieved.'));
    }));
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.FrequentComponents(), { once: true });
