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

// --- custom flags
var Dom = YAHOO.util.Dom;

function bmo_hide_tracking_flags() {
  for (var field in bmo_custom_flags) {
    var el = Dom.get(field);
    var value = el ? el.value : bmo_custom_flags[field];
    if (el && (value != bmo_custom_flags[field])) {
      bmo_show_tracking_flags();
      return;
    }
    if (value == '---') {
      Dom.addClass('row_' + field, 'bz_hidden');
    } else {
      Dom.addClass(field, 'bz_hidden');
      Dom.removeClass('ro_' + field, 'bz_hidden');
    }
  }
}

function bmo_show_tracking_flags() {
  Dom.addClass('edit_tracking_fields_action', 'bz_hidden');
  for (var field in bmo_custom_flags) {
    if (Dom.get(field).value == '---') {
      Dom.removeClass('row_' + field, 'bz_hidden');
    } else {
      Dom.removeClass(field, 'bz_hidden');
      Dom.addClass('ro_' + field, 'bz_hidden');
    }
  }
}
