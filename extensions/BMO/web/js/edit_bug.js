/* ***** BEGIN LICENSE BLOCK *****
 * Version: MPL 1.1
 * 
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 * 
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
 * for the specific language governing rights and limitations under the
 * License.
 * 
 * The Original Code is the BMO Bugzilla Extension;
 * 
 * The Initial Developer of the Original Code is the Mozilla Foundation.
 * Portions created by the Initial Developer are Copyright (C) 2011 the
 * Initial Developer. All Rights Reserved.
 * 
 * Contributor(s):
 *   Byron Jones <glob@mozilla.com>
 *
 * ***** END LICENSE BLOCK *****
 */

function init_clone_bug_menu(el, bug_id, product, component) {
  var diff_url = 'enter_bug.cgi?cloned_bug_id=' + bug_id;
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
