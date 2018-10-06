/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Show the current user's most-used components on the New Bug page.
 */
Bugzilla.NewBugFrequentComp = class NewBugFrequentComp {
  /**
   * Initialize a new NewBugFrequentComp instance.
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
          href: `/enter_bug.cgi?${params.toString()}`,
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
   * @param {Number} [max=10] Maximum number of results.
   * @returns {Promise} Results or error.
   */
  async fetch(max = 10) {
    const params = new URLSearchParams({
      email1: BUGZILLA.user.login,
      emailreporter1: '1',
      emailtype1: 'exact',
      chfield: '[Bug creation]',
      chfieldfrom: '-1y',
      chfieldto: 'Now',
      include_fields: 'product,component',
    });

    return new Promise((resolve, reject) => {
      bugzilla_ajax({
        url: `/rest/bug?${params.toString()}`
      }, response => {
        if (!response.bugs) {
          reject(new Error('Your frequent components could not be retrieved.'));

          return;
        }

        if (!response.bugs.length) {
          reject(new Error(('Your frequent components could not be found.')));

          return;
        }

        const results = [];

        for (const { product, component } of response.bugs) {
          const index = results.findIndex(result => product === result.product && component === result.component);

          if (index > -1) {
            results[index].count++;
          } else {
            results.push({ product, component, count: 1 });
          }
        }

        // Sort in descending order
        results.sort((a, b) => (a.count < b.count ? 1 : a.count > b.count ? -1 : 0));

        resolve(results.slice(0, max));
      }, () => {
        reject(new Error('Your frequent components could not be retrieved.'));
      });
    });
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.NewBugFrequentComp(), { once: true });
