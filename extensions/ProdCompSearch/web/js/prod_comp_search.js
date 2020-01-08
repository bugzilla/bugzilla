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
            const limit = that.data('max_results') + 1;

            that.devbridgeAutocomplete({
                appendTo: $('#main-inner'),
                forceFixPosition: true,
                deferRequestBy: 250,
                minChars: 3,
                maxHeight: 500,
                tabDisabled: true,
                autoSelectFirst: true,
                triggerSelectOnValidInput: false,
                width: '',
                lookup: (query, done) => {
                    // Note: `async` doesn't work for this `lookup` function, so use a `Promise` chain instead
                    Bugzilla.API.get(`prod_comp_search/find/${encodeURIComponent(query)}`, { limit })
                        .then(({ products }) => products.map(item => ({
                            value: `${item.product}${item.component ? ` :: ${item.component}` : ''}`,
                            data : item,
                        })))
                        .catch(() => [])
                        .then(suggestions => done({ suggestions }));
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

    const $input = document.querySelector('.prod_comp_search');

    // Check for product name passed with the URL hash, which was supported by the experimental new-bug page now
    // redirected to enter_bug.cgi, e.g. https://bugzilla.mozilla.org/new-bug#Firefox
    if ($input && location.pathname === `${BUGZILLA.config.basepath}enter_bug.cgi` && location.hash) {
        $input.value = location.hash.substr(1);
        $input.dispatchEvent(new InputEvent('input'));
    }
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

        params.set('product', product);
        params.set('component', component);

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
    try {
      const { results } = await Bugzilla.API.get('prod_comp_search/frequent');

      if (!results) {
        return Promise.reject(new Error('Your frequent components could not be retrieved.'));
      }

      if (!results.length) {
        return Promise.reject(new Error('Your frequent components could not be found.'));
      }

      return Promise.resolve(results);
    } catch (ex) {
      return Promise.reject(new Error('Your frequent components could not be retrieved.'));
    }
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.FrequentComponents(), { once: true });
