/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

YAHOO.util.Event.onDOMReady(function() {
    YAHOO.util.Event.addListener('defer-until', 'change', function() {
        YAHOO.util.Dom.get('defer-date').innerHTML = 'until ' + this.value;
    });
    bz_fireEvent(YAHOO.util.Dom.get('defer-until'), 'change');
});
