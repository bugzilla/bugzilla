/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    $('#shieldStudies').submit(function () {
        var short_desc = '[SHIELD] ' + encodeURIComponent($('#hypothesis').val());
        console.log(short_desc);
        $('#short_desc').val(short_desc);
        return true;
    });
});
