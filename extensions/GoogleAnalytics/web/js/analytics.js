/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

window.addEventListener('DOMContentLoaded', () => {
  'use strict';

  const $meta = document.querySelector('meta[name="google-analytics"]');

  if (!$meta) {
    return;
  }

  // Activate Google Analytics
  window.ga=window.ga||function(){(ga.q=ga.q||[]).push(arguments)};ga.l=+new Date;
  ga('create', $meta.content, 'auto');
  ga('set', 'anonymizeIp', true);
  ga('set', 'transport', 'beacon');
  // Record a crafted location (template name) and title instead of actual URL
  ga('set', 'location', $meta.dataset.location);
  ga('set', 'title', $meta.dataset.title);
  // Custom Dimension: logged in (true) or out (false)
  ga('set', 'dimension1', !!BUGZILLA.user.login);
  // Track page view
  ga('send', 'pageview');
}, { once: true });
