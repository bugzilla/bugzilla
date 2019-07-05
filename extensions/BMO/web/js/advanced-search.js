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
 * Reference or define the BMO extension namespace.
 * @namespace
 */
Bugzilla.BMO = Bugzilla.BMO || {};

/**
 * Implement Advanced Search page features.
 */
Bugzilla.BMO.AdvancedSearch = class AdvancedSearch {
  /**
   * Initialize a new AdvancedSearch instance.
   */
  constructor() {
    this.params = (new URL(document.location)).searchParams;
    this.$classifications = document.querySelector('#classification');

    this.hide_graveyard();
  }

  /**
   * Hide Graveyard products by selecting classifications other than Graveyard.
   */
  hide_graveyard() {
    // Give up if URL params contain certain fields
    if (this.params.has('classification') || this.params.has('product') || this.params.has('component')) {
      return;
    }

    // Select non-Graveyard classifications
    for (const $option of this.$classifications.options) {
      $option.selected = $option.value !== 'Graveyard';
    }

    // Fire an event to update the Product and Component lists
    this.$classifications.dispatchEvent(new Event('change'));
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.BMO.AdvancedSearch(), { once: true });
