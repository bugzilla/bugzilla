/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var Dom = YAHOO.util.Dom;

function toggle_options(visible, name) {
  var rows = Dom.getElementsByClassName(name + '_tr');
  for (var i = 0, l = rows.length; i < l; i++) {
    if (visible) {
      Dom.removeClass(rows[i], 'hidden');
    } else {
      Dom.addClass(rows[i], 'hidden');
    }
  }
}

function reset_to_defaults() {
  if (!push_defaults) return;
  for (var id in push_defaults) {
    var el = Dom.get(id);
    if (!el) continue;
    if (el.nodeName == 'INPUT') {
      el.value = push_defaults[id];
    } else if (el.nodeName == 'SELECT') {
      for (var i = 0, l = el.options.length; i < l; i++) {
        if (el.options[i].value == push_defaults[id]) {
          el.options[i].selected = true;
          break;
        }
      }
    }
  }
}
