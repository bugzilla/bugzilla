/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

function editComment(comment_count, comment_id) {
    if (!comment_count || !comment_id) return;

    var edit_comment_textarea = YAHOO.util.Dom.get('edit_comment_textarea_' + comment_count);
    if (!YAHOO.util.Dom.hasClass(edit_comment_textarea, 'bz_default_hidden')) {
        hideEditCommentField(comment_count);
        return;
    }

    // Show the loading indicator
    toggleCommentLoading(comment_count);

    YAHOO.util.Connect.setDefaultPostHeader('application/json', true);
    YAHOO.util.Connect.asyncRequest(
        'POST',
        'jsonrpc.cgi',
        {
            success: function(res) {
                // Hide the loading indicator
                toggleCommentLoading(comment_count);
                data = YAHOO.lang.JSON.parse(res.responseText);
                if (data.error) {
                    alert("Get [% comment failed: " + data.error.message);
                }
                else if (data.result.comments[comment_id]) {
                    var comment_text = data.result.comments[comment_id];
                    showEditCommentField(comment_count, comment_text);
                }
            },
            failure: function(res) {
                // Hide the loading indicator
                toggleCommentLoading(comment_count);
                if (res.responseText) {
                    alert("Get comment failed: " + res.responseText);
                }
            }
        },
        YAHOO.lang.JSON.stringify({
            version: "1.1",
            method: "EditComments.comments",
            id: comment_id,
            params: { comment_ids: [ comment_id ] }
        })
    );
}

function hideEditCommentField(comment_count) {
    var comment_text_pre = YAHOO.util.Dom.get('comment_text_' + comment_count);
    YAHOO.util.Dom.removeClass(comment_text_pre, 'bz_default_hidden');

    var edit_comment_textarea = YAHOO.util.Dom.get('edit_comment_textarea_' + comment_count);
    YAHOO.util.Dom.addClass(edit_comment_textarea, 'bz_default_hidden');
    edit_comment_textarea.disabled = true;

    YAHOO.util.Dom.get("edit_comment_edit_link_" + comment_count).innerHTML = "edit";
}

function showEditCommentField(comment_count, comment_text) {
    var comment_text_pre = YAHOO.util.Dom.get('comment_text_' + comment_count);
    YAHOO.util.Dom.addClass(comment_text_pre, 'bz_default_hidden');

    var edit_comment_textarea = YAHOO.util.Dom.get('edit_comment_textarea_' + comment_count);
    YAHOO.util.Dom.removeClass(edit_comment_textarea, 'bz_default_hidden');
    edit_comment_textarea.disabled = false;
    edit_comment_textarea.value = comment_text;

    YAHOO.util.Dom.get("edit_comment_edit_link_" + comment_count).innerHTML = "unedit";
}

function toggleCommentLoading(comment_count, hide) {
    var comment_div = 'comment_text_' + comment_count;
    var loading_div = 'edit_comment_loading_' + comment_count;
    if (YAHOO.util.Dom.hasClass(loading_div, 'bz_default_hidden')) {
        YAHOO.util.Dom.addClass(comment_div, 'bz_default_hidden');
        YAHOO.util.Dom.removeClass(loading_div, 'bz_default_hidden');
    }
    else {
        YAHOO.util.Dom.removeClass(comment_div, 'bz_default_hidden');
        YAHOO.util.Dom.addClass(loading_div, 'bz_default_hidden');
    }
}

