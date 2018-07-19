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
var Bugzilla = Bugzilla || {};

/**
 * Implement the one-click Component Watching functionality that can be added to any page.
 * @abstract
 */
Bugzilla.ComponentWatching = class ComponentWatching {
  /**
   * Initialize a new ComponentWatching instance. Since constructors can't be async, use a separate function to move on.
   */
  constructor() {
    this.buttons = document.querySelectorAll('button.component-watching');

    this.init();
  }

  /**
   * Send a REST API request, and return the results in a Promise.
   * @param {Object} [request={}] Request data. If omitted, all the current watches will be returned.
   * @param {String} [path=''] Optional path to be appended to the request URL.
   * @returns {Promise<Object|String>} Response data or error message.
   */
  async fetch(request = {}, path = '') {
    request.url = `/rest/component-watching${path}`;

    return new Promise((resolve, reject) => bugzilla_ajax(request, data => resolve(data), error => reject(error)));
  }

  /**
   * Start watching the current product or component.
   * @param {String} product Product name.
   * @param {String} [component=''] Component name. If omitted, all the components in the product will be watched.
   * @returns {Promise<Object|String>} Response data or error message.
   */
  async watch(product, component = '') {
    return this.fetch({ type: 'POST', data: { product, component } });
  }

  /**
   * Stop watching the current product or component.
   * @param {Number} id ID of the watch to be removed.
   * @returns {Promise<Object|String>} Response data or error message.
   */
  async unwatch(id) {
    return this.fetch({ type: 'DELETE' }, `/${id}`);
  }

  /**
   * Log an event with Google Analytics if possible. For privacy reasons, we don't send any specific product or
   * component name.
   * @param {String} source Event source that will be part of the event category.
   * @param {String} action `watch` or `unwatch`.
   * @param {String} type `product` or `component`.
   * @param {Number} code `0` for a successful change, `1` otherwise.
   * @see https://developers.google.com/analytics/devguides/collection/analyticsjs/events
   */
  track_event(source, action, type, code) {
    if ('ga' in window) {
      ga('send', 'event', `Component Watching: ${source}`, action, type, code);
    }
  }

  /**
   * Show a short floating message if the button is on BugModal. This code is from bug_modal.js, requiring jQuery.
   * @param {String} message Message text.
   */
  show_message(message) {
    if (!document.querySelector('#floating-message')) {
      return;
    }

    $('#floating-message-text').text(message);
    $('#floating-message').fadeIn(250).delay(2500).fadeOut();
  }

  /**
   * Get all the component watching buttons on the current page.
   * @param {String} [product] Optional product name.
   * @param {String} [component] Optional component name.
   * @returns {HTMLButtonElement[]} List of button elements.
   */
  get_buttons(product = undefined, component = undefined) {
    let buttons = [...this.buttons];

    if (product) {
      buttons = buttons.filter($button => $button.dataset.product === product);
    }

    if (component) {
      buttons = buttons.filter($button => $button.dataset.component === component);
    }

    return buttons;
  }

  /**
   * Update a Watch/Unwatch button for a product or component.
   * @param {HTMLButtonElement} $button Button element to be updated.
   * @param {Boolean} disabled Whether the button has to be disabled.
   * @param {Number} [watchId] Optional watch ID if the product or component is being watched.
   */
  update_button($button, disabled, watchId = undefined) {
    const { product, component } = $button.dataset;

    if (watchId) {
      $button.dataset.watchId = watchId;
      $button.textContent = $button.getAttribute('data-label-unwatch') || 'Unwatch';
      $button.title = component ?
        `Stop watching the ${component} component` :
        `Stop watching all components in the ${product} product`;
    } else {
      delete $button.dataset.watchId;

      $button.textContent = $button.getAttribute('data-label-watch') || 'Watch';
      $button.title = component ?
        `Start watching the ${component} component` :
        `Start watching all components in the ${product} product`;
    }

    $button.disabled = disabled;
  }

  /**
   * Called whenever a Watch/Unwatch button is clicked. Send a request to update the user's watch list, and update the
   * relevant buttons on the page.
   * @param {HTMLButtonElement} $button Clicked button element.
   */
  async button_onclick($button) {
    const { product, component, watchId, source } = $button.dataset;
    let message = '';
    let code = 0;

    // Disable the button until the request is complete
    $button.disabled = true;

    try {
      if (watchId) {
        await this.unwatch(watchId);

        if (component) {
          message = `You are no longer watching the ${component} component`;

          this.get_buttons(product, component).forEach($button => this.update_button($button, false));
        } else {
          message = `You are no longer watching all components in the ${product} product`;

          this.get_buttons(product).forEach($button => this.update_button($button, false));
        }
      } else {
        const watch = await this.watch(product, component);

        if (component) {
          message = `You are now watching the ${component} component`;

          this.get_buttons(product, component).forEach($button => this.update_button($button, false, watch.id));
        } else {
          message = `You are now watching all components in the ${product} product`;

          this.get_buttons(product).forEach($button => {
            if ($button.dataset.component) {
              this.update_button($button, true);
            } else {
              this.update_button($button, false, watch.id);
            }
          });
        }
      }
    } catch (ex) {
      message = 'Your watch list could not be updated. Please try again later.';
      code = 1;
    }

    this.show_message(message);
    this.track_event(source, watchId ? 'unwatch' : 'watch', component ? 'component' : 'product', code);
  }

  /**
   * Retrieve the current watch list, and initialize all the buttons.
   */
  async init() {
    try {
      const all_watches = await this.fetch();

      this.get_buttons().forEach($button => {
        const { product, component } = $button.dataset;
        const watches = all_watches.filter(watch => watch.product_name === product);
        const product_watch = watches.find(watch => !watch.component);

        if (!component) {
          // This button is for product watching
          this.update_button($button, false, product_watch ? product_watch.id : undefined);
        } else if (product_watch) {
          // Disabled the button because all the components in the product is being watched
          this.update_button($button, true);
        } else {
          const watch = watches.find(watch => watch.component_name === component);

          this.update_button($button, false, watch ? watch.id : undefined);
        }

        $button.addEventListener('click', () => this.button_onclick($button));
      });
    } catch (ex) {}
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.ComponentWatching(), { once: true });
