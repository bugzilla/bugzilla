/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var shadow_bug = {
    init: function() {
        var Dom = YAHOO.util.Dom;
        var comment_divs = Dom.getElementsByClassName('bz_comment', 'div', 'comments');
        var comments = new Array();
        for (var i = 0, l = comment_divs.length; i < l; i++) {
            var time_spans = Dom.getElementsByClassName('bz_comment_time', 'span', comment_divs[i]);
            if (!time_spans.length) continue;
            var date = this.parse_date(time_spans[0].innerHTML);
            if (!date) continue;

            var comment = {};
            comment.div = comment_divs[i];
            comment.date = date;
            comment.shadow = Dom.hasClass(comment.div, 'shadow_bug_comment');
            comments.push(comment);
        }

        for (var i = 0, l = comments.length; i < l; i++) {
            if (!comments[i].shadow) continue;
            for (var j = 0, jl = comments.length; j < jl; j++) {
                if (comments[j].shadow) continue;
                if (comments[j].date > comments[i].date) {
                    comments[j].div.parentNode.insertBefore(comments[i].div, comments[j].div);
                    break;
                }
            }
            Dom.removeClass(comments[i].div, 'bz_default_hidden');
        }

        Dom.get('comment').placeholder = 'Add non-public comment';
    },

    parse_date: function(date) {
        var matches = date.match(/^\s*(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
        if (!matches) return;
        return (matches[1] + matches[2] + matches[3] + matches[4] + matches[5] + matches[6]) + 0;
    }
};


YAHOO.util.Event.onDOMReady(function() {
    shadow_bug.init();
});
