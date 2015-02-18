/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(document).ready(function() {
    'use strict';

    $('#tmRequestForm').submit(function (event) {
        var mozillian_re = /^https?:\/\/mozillians.org\/([^\/]+\/)?u\/[^\/]+$/i;
        var errors = [];
        var missing = false;

        $('label.required').each(function (index) {
            var id = $(this).attr("for");
            var input = $("#" + id);

            if (input.val() == "") {
                input.addClass("missing");
                missing = true;
                event.preventDefault();
            }
            else {
                input.removeClass("missing");
            }
        });

        if (missing) {
            errors.push("There are missing required fields");
        }

        if (errors.length) {
            alert(errors.join("\n"));
            event.preventDefault();
            return;
        }

        $('#short_desc').val(
            "IT Discourse Request: " + $('#community').val() + ' (' + $('#name').val() + ')'
        );
    });
});
