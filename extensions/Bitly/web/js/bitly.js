/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

(function() {
    'use strict';
    var Dom = YAHOO.util.Dom;
    YAHOO.namespace('bitly');
    var bitly = YAHOO.bitly;

    bitly.dialog = false;
    bitly.url = { shorten: '', list: '' };

    bitly.shorten = function() {
        if (this.dialog) {
            this.dialog.show();
            var el = Dom.get('bitly_url');
            el.select();
            el.focus();
            return;
        }
        this.dialog = new YAHOO.widget.Overlay('bitly_overlay', {
            visible: true,
            close: false,
            underlay: 'shadow',
            width: '400px',
            context: [ 'bitly_shorten', 'bl', 'tl', ['windowResize'], [0, -10] ]
        });
        this.dialog.render(document.body);

        YAHOO.util.Event.addListener('bitly_close', 'click', function() {
            YAHOO.bitly.dialog.hide();
        });
        YAHOO.util.Event.addListener('bitly_url', 'keypress', function(o) {
            if (o.keyCode == 27 || o.keyCode == 13)
                YAHOO.bitly.dialog.hide();
        });
        this.execute();
        Dom.get('bitly_url').focus();
    };

    bitly.execute = function() {
        Dom.get('bitly_url').value = '';

        var type = Dom.get('bitly_type').value;
        if (this.url[type]) {
            this.set(this.url[type]);
            return;
        }

        var url = 'rest/bitly/' + type + '?url=' + encodeURIComponent(document.location);
        YAHOO.util.Connect.initHeader("Accept", "application/json");
        YAHOO.util.Connect.asyncRequest('GET', url, {
            success: function(o) {
                var response = YAHOO.lang.JSON.parse(o.responseText);
                if (response.error) {
                    bitly.set(response.message);
                }
                else {
                    bitly.url[type] = response.url;
                    bitly.set(response.url);
                }
            },
            failure: function(o) {
                try {
                    var response = YAHOO.lang.JSON.parse(o.responseText);
                    if (response.error) {
                        bitly.set(response.message);
                    }
                    else {
                        bitly.set(o.statusText);
                    }
                } catch (ex) {
                    bitly.set(o.statusText);
                }
            }
        });
    };

    bitly.set = function(value) {
        var el = Dom.get('bitly_url');
        el.value = value;
        el.select();
        el.focus();
    };

    bitly.toggle = function() {
        if (this.dialog
            && YAHOO.util.Dom.get('bitly_overlay').style.visibility == 'visible')
        {
            this.dialog.hide();
        }
        else {
            this.shorten();
        }
    };
})();
