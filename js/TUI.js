/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

/* This file provides JavaScript functions to be included when one wishes
 * to show/hide certain UI elements, and have the state of them being
 * shown/hidden stored in a cookie.
 * 
 * TUI stands for Tweak UI.
 *
 * Requires js/util.js and jquery
 *
 * See template/en/default/bug/create/create.html.tmpl for a usage example.
 */

var TUI_HIDDEN_CLASS = 'bz_tui_hidden';
var TUI_COOKIE_NAME  = 'TUI';
var TUI_alternates   = {};
var TUI              = {};

/** 
 * Hides a particular class of elements if they are shown, 
 * or shows them if they are hidden. Then it stores whether that
 * class is now hidden or shown.
 *
 * @param className   The name of the CSS class to hide.
 */
function TUI_toggle_class(className) {
    var elements = [];
    $("." + className).each(function(i, el) {
        bz_toggleClass(el, TUI_HIDDEN_CLASS);
        elements.push(el);
    });
    _TUI_save_class_state(elements, className);
    _TUI_toggle_control_link(className);
}


/**
 * Specifies that a certain class of items should be hidden by default,
 * if the user doesn't have a TUI cookie.
 * 
 * @param className   The class to hide by default.
 */
function TUI_hide_default(className) {
    $(document).ready(function () {
        if (!TUI[className]) {
            TUI_toggle_class(className);
        }
    });
}

function _TUI_toggle_control_link(className) {
    $("#" + className + "_controller").each(function(i, link) {
        var original_text = link.innerHTML;
        link.innerHTML = TUI_alternates[className];
        TUI_alternates[className] = original_text;
    });
}

function _TUI_save_class_state(elements, aClass) {
    // We just check the first element to see if it's hidden or not, and
    // consider that all elements are the same.
    if ($(elements[0]).hasClass(TUI_HIDDEN_CLASS)) {
        _TUI_store(aClass, false);
    }
    else {
        _TUI_store(aClass, true);
    }
}

function _TUI_store(aClass, state) {
    TUI[aClass] = state;
    localStorage.setItem(TUI_COOKIE_NAME, JSON.stringify(TUI));
}

function _TUI_restore() {
    var tui_json = localStorage.getItem(TUI_COOKIE_NAME);
    TUI = JSON.parse(tui_json);
    if (!TUI)
      TUI = {};
    for (yui_item in TUI) {
        if (!TUI[yui_item]) {
            $("." + yui_item).each(function (i, el) {
                $(el).addClass(TUI_HIDDEN_CLASS);
            });
            _TUI_toggle_control_link(yui_item);
        }
    }
}

$(document).ready(_TUI_restore);
