/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
  var meta = $('meta[name="google-analytics"]');

  if (typeof Mozilla.dntEnabled === 'function' && !Mozilla.dntEnabled() && meta.length) {
    // Activate Google Analytics
    window.ga=window.ga||function(){(ga.q=ga.q||[]).push(arguments)};ga.l=+new Date;
    ga('create', meta.attr('content'), 'auto');
    ga('set', 'anonymizeIp', true);
    ga('set', 'location', meta.data('location'));
    ga('set', 'title', meta.data('title'));
    ga('set', 'transport', 'beacon');
    // Track page view
    ga('send', 'pageview');
  }
});
