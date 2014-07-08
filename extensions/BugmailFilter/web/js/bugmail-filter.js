/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var Dom = YAHOO.util.Dom;
var Event = YAHOO.util.Event;

function onFilterProductChange() {
    selectProduct(Dom.get('product'), Dom.get('component'), null, null, '__Any__');
    Dom.get('component').disabled = Dom.get('product').value == '';
}

function onFilterActionChange() {
    var value = Dom.get('action').value;
    Dom.get('add_filter').disabled = value == '';
}

function onRemoveChange() {
  var cbs = Dom.get('filters_table').getElementsByTagName('input');
  for (var i = 0, l = cbs.length; i < l; i++) {
    if (cbs[i].checked) {
      Dom.get('remove').disabled = false;
      return;
    }
  }
  Dom.get('remove').disabled = true;
}

Event.onDOMReady(function() {
    Event.on('action', 'change', onFilterActionChange);
    onFilterProductChange();
    onFilterActionChange();
    onRemoveChange();
});
