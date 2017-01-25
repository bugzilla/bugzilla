/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

function show_usermenu(id, email, show_edit) {
    var items = [
        {
            name: "Profile",
            callback: function () {
                var href = "user_profile?login=" + encodeURIComponent(email);
                window.open(href, "_blank");
            }
        },
        {
            name: "Activity",
            callback: function () {
                var href = "page.cgi?id=user_activity.html&action=run&from=-14d&who=" + encodeURIComponent(email);
                window.open(href, "_blank");
            }
        },
        {
            name: "Mail",
            callback: function () {
                var href = "mailto:" + encodeURIComponent(email);
                window.open(href, "_blank");
            }
        }
    ];
    if (show_edit) {
        items.push({
            name: "Edit",
            callback: function () {
                var href = "editusers.cgi?action=edit&userid=" + id;
                window.open(href, "_blank");
            }
        });
    }
    $.contextMenu({
        selector: ".vcard_" + id,
        trigger: "left",
        items: items
    });
}

$(function() {
  $('.show_usermenu').on("click", function (event) {
    var $this = $(this);
    return show_usermenu($this.data('user-id'), $this.data('user-email'), $this.data('show-edit'));
  });
});
