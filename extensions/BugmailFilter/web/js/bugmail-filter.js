/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var Dom = YAHOO.util.Dom;

function onFilterFieldChange() {
    if (Dom.get('field').value == '~') {
        Dom.removeClass('field_contains_row', 'bz_default_hidden');
        Dom.get('field_contains').focus();
        Dom.get('field_contains').select();
    }
    else {
        Dom.addClass('field_contains_row', 'bz_default_hidden');
    }
}

function onFilterProductChange() {
    selectProduct(Dom.get('product'), Dom.get('component'), null, null, '__Any__');
    Dom.get('component').disabled = Dom.get('product').value == '';
}

function setFilterAddEnabled() {
    Dom.get('add_filter').disabled =
        (
            Dom.get('field').value == '~'
            && Dom.get('field_contains').value == ''
        )
        || Dom.get('action').value == '';
}

function onFilterRemoveChange() {
  var cbs = Dom.get('filters_table').getElementsByTagName('input');
  for (var i = 0, l = cbs.length; i < l; i++) {
    if (cbs[i].checked) {
      Dom.get('remove').disabled = false;
      return;
    }
  }
  Dom.get('remove').disabled = true;
}

function showAllFlags() {
    Dom.addClass('show_all', 'bz_default_hidden');
    Dom.removeClass('all_flags', 'bz_default_hidden');
}

YAHOO.util.Event.onDOMReady(function() {
    YAHOO.util.Event.on('field',          'change',   onFilterFieldChange);
    YAHOO.util.Event.on('field_contains', 'keyup',    setFilterAddEnabled);
    YAHOO.util.Event.on('product',        'change',   onFilterProductChange);
    YAHOO.util.Event.on('action',         'change',   setFilterAddEnabled);
    onFilterFieldChange();
    onFilterProductChange();
    onFilterRemoveChange();
    setFilterAddEnabled();
});
