/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

function getPreSelectedIndex(el) {
    var options = el.options;
    for (var i = 0, l = options.length; i < l; i++) {
        var attributes = options[i].attributes;
        for (var j = 0, m = attributes.length; j < m; j++) {
            if (attributes[j].name == 'selected') {
                return i;
            }
        }
    }
    return 0;
}

// Force the browser to honour the selected option when a page is refreshed,
// but if the user hasn't explicitly selected a different option.
YAHOO.util.Event.onDOMReady(function() {
    var selects = document.getElementById('changeform').getElementsByTagName('select');
    for (var i = 0, l = selects.length; i < l; i++) {
        var el = selects[i];
        var el_dirty = document.getElementById(el.name + '_dirty');
        if (el_dirty) {
            if (!el_dirty.value) {
                el.selectedIndex = getPreSelectedIndex(el);
            }
            YAHOO.util.Event.on(el, "change", function(e) {
                var el = e.target;
                var preSelectedIndex = getPreSelectedIndex(el);
                document.getElementById(el.name + '_dirty').value = preSelectedIndex == el.selectedIndex ? '' : '1';
            });
        }
    }
});
