/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    'use strict';
    var popup, urls = [];

    async function execute() {
        var type = $('#bitly-type').val();

        if (urls[type]) {
            $('#bitly-url').val(urls[type]).select().focus();
            return;
        }

        $('#bitly-url').val('');

        try {
            const { url } = await Bugzilla.API.get(`bitly/${type}`, { url: $('#bitly-shorten').data('url') });

            urls[type] = url;
            $('#bitly-url').val(urls[type]).select().focus();
        } catch ({ message }) {
            $('#bitly-url').val(message);
        }
    }

    $('#bitly-shorten')
        .click(function(event) {
            event.preventDefault();
            popup = $('#bitly-overlay').bPopup({
                speed: 100,
                followSpeed: 100,
                modalColor: '#fff'
            }, execute);
        });

    $('#bitly-type')
        .change(execute);

    $('#bitly-close')
        .click(function(event) {
            event.preventDefault();
            popup.close();
        });
});
