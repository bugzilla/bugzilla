/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

function init_clone_bug_menu(el, bug_id, product, component) {
  var diff_url = 'enter_bug.cgi?format=__default__&cloned_bug_id=' + bug_id;
  var cur_url = diff_url +
    '&product=' + encodeURIComponent(product) +
    '&component=' + encodeURIComponent(component);
  var menu = new YAHOO.widget.Menu('clone_bug_menu', { position : 'dynamic' });
  menu.addItems([
    { text: 'Clone to the current product', url: cur_url },
    { text: 'Clone to a different product', url: diff_url }
  ]);
  menu.render(document.body);
  YAHOO.util.Event.addListener(el, 'click', show_clone_bug_menu, menu);
}

function show_clone_bug_menu(event, menu) {
  menu.cfg.setProperty('xy', YAHOO.util.Event.getXY(event));
  menu.show();
  event.preventDefault();
}

// -- make attachment table, comments, new comment textarea equal widths

YAHOO.util.Event.onDOMReady(function() {
  var comment_tables = Dom.getElementsByClassName('bz_comment_table', 'table', 'comments');
  if (comment_tables.length) {
    var comment_width = comment_tables[0].getElementsByTagName('td')[0].clientWidth + 'px';
    var attachment_table = Dom.get('attachment_table');
    if (attachment_table)
      attachment_table.style.width = comment_width;
    var new_comment = Dom.get('comment');
    if (new_comment)
      new_comment.style.width = comment_width;
  }
});
