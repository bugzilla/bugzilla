/* The contents of this file are subject to the Mozilla Public
 * License Version 1.1 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy of
 * the License at http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS
 * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * The Original Code is the Bugzilla Bug Tracking System.
 *
 * The Initial Developer of the Original Code is Netscape Communications
 * Corporation. Portions created by Netscape are
 * Copyright (C) 1998 Netscape Communications Corporation. All
 * Rights Reserved.
 *
 * Contributor(s): Frédéric Buclin <LpSolit@gmail.com>
 *                 Max Kanat-Alexander <mkanat@bugzilla.org>
 *                 Edmund Wong <ewong@pw-wspx.org>
 */

function updateCommentPrivacy(checkbox, id) {
    var comment_elem = document.getElementById('comment_text_'+id).parentNode;
    if (checkbox.checked) {
      if (!comment_elem.className.match('bz_private')) {
        comment_elem.className = comment_elem.className.concat(' bz_private');
      }
    }
    else {
      comment_elem.className =
        comment_elem.className.replace(/(\s*|^)bz_private(\s*|$)/, '$2');
    }
}

/* The functions below expand and collapse comments  */

function toggle_comment_display(link, comment_id) {
    var comment = document.getElementById('comment_text_' + comment_id);
    var re = new RegExp(/\bcollapsed\b/);
    if (comment.className.match(re))
        expand_comment(link, comment);
    else
        collapse_comment(link, comment);
}

function toggle_all_comments(action) {
    // If for some given ID the comment doesn't exist, this doesn't mean
    // there are no more comments, but that the comment is private and
    // the user is not allowed to view it.

    var comments = YAHOO.util.Dom.getElementsByClassName('bz_comment_text');
    for (var i = 0; i < comments.length; i++) {
        var comment = comments[i];
        if (!comment)
            continue;

        var id = comments[i].id.match(/\d*$/);
        var link = document.getElementById('comment_link_' + id);
        if (action == 'collapse')
            collapse_comment(link, comment);
        else
            expand_comment(link, comment);
    }
}

function collapse_comment(link, comment) {
    link.innerHTML = "[+]";
    link.title = "Expand the comment.";
    YAHOO.util.Dom.addClass(comment, 'collapsed');
}

function expand_comment(link, comment) {
    link.innerHTML = "[-]";
    link.title = "Collapse the comment";
    YAHOO.util.Dom.removeClass(comment, 'collapsed');
}

/* This way, we are sure that browsers which do not support JS
   * won't display this link  */

function addCollapseLink(count) {
    document.write(' <a href="#" class="bz_collapse_comment"' +
                   ' id="comment_link_' + count +
                   '" onclick="toggle_comment_display(this, ' +  count +
                   '); return false;" title="Collapse the comment.">[-]<\/a> ');
}

function goto_add_comments( anchor ){
    anchor =  (anchor || "add_comment");
    // we need this line to expand the comment box
    document.getElementById('comment').focus();
    setTimeout(function(){ 
        document.location.hash = anchor;
        // firefox doesn't seem to keep focus through the anchor change
        document.getElementById('comment').focus();
    },10);
    return false;
}
