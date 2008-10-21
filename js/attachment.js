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
 * Contributor(s): Myk Melez <myk@mozilla.org>
 *                 Joel Peshkin <bugreport@peshkin.net>
 *                 Erik Stambaugh <erik@dasbistro.com>
 *                 Marc Schumann <wurblzap@gmail.com>
 */

function updateCommentPrivacy(checkbox) {
    var text_elem = document.getElementById('comment');
    if (checkbox.checked) {
        text_elem.className='bz_private';
    } else {
        text_elem.className='';
    }
}

function setContentTypeDisabledState(form)
{
    var isdisabled = false;
    if (form.ispatch.checked)
        isdisabled = true;

    for (var i=0 ; i<form.contenttypemethod.length ; i++)
        form.contenttypemethod[i].disabled = isdisabled;

    form.contenttypeselection.disabled = isdisabled;
    form.contenttypeentry.disabled = isdisabled;
}

function URLFieldHandler() {
    var field_attachurl = document.getElementById("attachurl");
    var greyfields = new Array("data", "ispatch", "autodetect",
                               "list", "manual", "bigfile",
                               "contenttypeselection",
                               "contenttypeentry");
    var i, thisfield;
    if (field_attachurl.value.match(/^\s*$/)) {
        for (i = 0; i < greyfields.length; i++) {
            thisfield = document.getElementById(greyfields[i]);
            if (thisfield) {
                thisfield.removeAttribute("disabled");
            }
        }
    } else {
        for (i = 0; i < greyfields.length; i++) {
            thisfield = document.getElementById(greyfields[i]);
            if (thisfield) {
                thisfield.setAttribute("disabled", "disabled");
            }
        }
    }
}

function DataFieldHandler() {
    var field_data = document.getElementById("data");
    var greyfields = new Array("attachurl");
    var i, thisfield;
    if (field_data.value.match(/^\s*$/)) {
        for (i = 0; i < greyfields.length; i++) {
            thisfield = document.getElementById(greyfields[i]);
            if (thisfield) {
                thisfield.removeAttribute("disabled");
            }
        }
    } else {
        for (i = 0; i < greyfields.length; i++) {
            thisfield = document.getElementById(greyfields[i]);
            if (thisfield) {
                thisfield.setAttribute("disabled", "disabled");
            }
        }
    }
}

function clearAttachmentFields() {
    var element;

    document.getElementById('data').value = '';
    DataFieldHandler();
    if ((element = document.getElementById('bigfile')))
        element.checked = '';
    if ((element = document.getElementById('attachurl'))) {
        element.value = '';
        URLFieldHandler();
    }
    document.getElementById('description').value = '';
    document.getElementById('ispatch').checked = '';
    if ((element = document.getElementById('isprivate')))
        element.checked = '';
}

/* Functions used when viewing patches in Diff mode. */

function collapse_all() {
  var elem = document.checkboxform.firstChild;
  while (elem != null) {
    if (elem.firstChild != null) {
      var tbody = elem.firstChild.nextSibling;
      if (tbody.className == 'file') {
        tbody.className = 'file_collapse';
        twisty = get_twisty_from_tbody(tbody);
        twisty.firstChild.nodeValue = '(+)';
        twisty.nextSibling.checked = false;
      }
    }
    elem = elem.nextSibling;
  }
  return false;
}

function expand_all() {
  var elem = document.checkboxform.firstChild;
  while (elem != null) {
    if (elem.firstChild != null) {
      var tbody = elem.firstChild.nextSibling;
      if (tbody.className == 'file_collapse') {
        tbody.className = 'file';
        twisty = get_twisty_from_tbody(tbody);
        twisty.firstChild.nodeValue = '(-)';
        twisty.nextSibling.checked = true;
      }
    }
    elem = elem.nextSibling;
  }
  return false;
}

var current_restore_elem;

function restore_all() {
  current_restore_elem = null;
  incremental_restore();
}

function incremental_restore() {
  if (!document.checkboxform.restore_indicator.checked) {
    return;
  }
  var next_restore_elem;
  if (current_restore_elem) {
    next_restore_elem = current_restore_elem.nextSibling;
  } else {
    next_restore_elem = document.checkboxform.firstChild;
  }
  while (next_restore_elem != null) {
    current_restore_elem = next_restore_elem;
    if (current_restore_elem.firstChild != null) {
      restore_elem(current_restore_elem.firstChild.nextSibling);
    }
    next_restore_elem = current_restore_elem.nextSibling;
  }
}

function restore_elem(elem, alertme) {
  if (elem.className == 'file_collapse') {
    twisty = get_twisty_from_tbody(elem);
    if (twisty.nextSibling.checked) {
      elem.className = 'file';
      twisty.firstChild.nodeValue = '(-)';
    }
  } else if (elem.className == 'file') {
    twisty = get_twisty_from_tbody(elem);
    if (!twisty.nextSibling.checked) {
      elem.className = 'file_collapse';
      twisty.firstChild.nodeValue = '(+)';
    }
  }
}

function twisty_click(twisty) {
  tbody = get_tbody_from_twisty(twisty);
  if (tbody.className == 'file') {
    tbody.className = 'file_collapse';
    twisty.firstChild.nodeValue = '(+)';
    twisty.nextSibling.checked = false;
  } else {
    tbody.className = 'file';
    twisty.firstChild.nodeValue = '(-)';
    twisty.nextSibling.checked = true;
  }
  return false;
}

function get_tbody_from_twisty(twisty) {
  return twisty.parentNode.parentNode.parentNode.nextSibling;
}
function get_twisty_from_tbody(tbody) {
  return tbody.previousSibling.firstChild.nextSibling.firstChild.firstChild;
}
