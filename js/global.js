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
* Contributor(s): 
*   Guy Pyrzak <guy.pyrzak@gmail.com>
*   Max Kanat-Alexander <mkanat@bugzilla.org>
*                 
*/

var BUGZILLA = $("#bugzilla-global").data("bugzilla");

$(function () {
  $('body').addClass("platform-" + navigator.platform);
  $('.show_mini_login_form').on("click", function (event) {
    return show_mini_login_form($(this).data('qs-suffix'));
  });
  $('.hide_mini_login_form').on("click", function (event) {
    return hide_mini_login_form($(this).data('qs-suffix'));
  });
  $('.show_forgot_form').on("click", function (event) {
    return show_forgot_form($(this).data('qs-suffix'));
  });
  $('.hide_forgot_form').on("click", function (event) {
    return hide_forgot_form($(this).data('qs-suffix'));
  });
  $('.check_mini_login_fields').on("click", function (event) {
    return check_mini_login_fields($(this).data('qs-suffix'));
  });
  $('.quicksearch_check_empty').on("submit", function (event) {
      if (this.quicksearch.value == '') {
          alert('Please enter one or more search terms first.');
          event.preventDefault();
      }
  });

  unhide_language_selector();
  $("#lob_action").on("change", update_text);
  $("#lob_newqueryname").on("keyup", manage_old_lists);
});

function unhide_language_selector() {
    $('#lang_links_container').removeClass('bz_default_hidden');
}

function update_text() {
    // 'lob' means list_of_bugs.
    var lob_action = document.getElementById('lob_action');
    var action = lob_action.options[lob_action.selectedIndex].value;
    var text = document.getElementById('lob_direction');
    var new_query_text = document.getElementById('lob_new_query_text');

    if (action == "add") {
        text.innerHTML = "to";
        new_query_text.style.display = 'inline';
    }
    else {
        text.innerHTML = "from";
        new_query_text.style.display = 'none';
    }
}

function manage_old_lists() {
    var old_lists = document.getElementById('lob_oldqueryname');
    // If there is no saved searches available, returns.
    if (!old_lists) return;

    var new_query = document.getElementById('lob_newqueryname').value;

    if (new_query != "") {
        old_lists.disabled = true;
    }
    else {
        old_lists.disabled = false;
    }
}


function show_mini_login_form( suffix ) {
    $('#login_link' + suffix).addClass('bz_default_hidden');
    $('#mini_login' + suffix).removeClass('bz_default_hidden');
    $('#new_account_container' + suffix).addClass('bz_default_hidden');
    return false;
}

function hide_mini_login_form( suffix ) {
    $('#login_link' + suffix).removeClass('bz_default_hidden');
    $('#mini_login' + suffix).addClass('bz_default_hidden');
    $('#new_account_container' + suffix).removeClass('bz_default_hidden');
    return false;
}

function show_forgot_form( suffix ) {
    $('#forgot_link' + suffix).addClass('bz_default_hidden');
    $('#forgot_form' + suffix).removeClass('bz_default_hidden');
    $('#login_container' + suffix).addClass('bz_default_hidden');
    return false;
}


function hide_forgot_form( suffix ) {
    $('#forgot_link' + suffix).removeClass('bz_default_hidden');
    $('#forgot_form' + suffix).addClass('bz_default_hidden');
    $('#login_container' + suffix).removeClass('bz_default_hidden');
    return false;
}

function init_mini_login_form( suffix ) {
    var mini_login = document.getElementById('Bugzilla_login' +  suffix );
    var mini_password = document.getElementById('Bugzilla_password' +  suffix );
    var mini_dummy = document.getElementById('Bugzilla_password_dummy' + suffix);
    // If the login and password are blank when the page loads, we display
    // "login" and "password" in the boxes by default.
    if (mini_login.value == "" && mini_password.value == "") {
        YAHOO.util.Dom.addClass(mini_password, 'bz_default_hidden');
        YAHOO.util.Dom.removeClass(mini_dummy, 'bz_default_hidden');
    }
    else {
        show_mini_login_form(suffix);
    }
}

function check_mini_login_fields( suffix ) {
    var mini_login = document.getElementById('Bugzilla_login' +  suffix );
    var mini_password = document.getElementById('Bugzilla_password' +  suffix );
    if (mini_login.value != "" && mini_password.value != "") {
        return true;
    } else {
        window.alert("You must provide the email address and password before logging in.");
        return false;
    }
}

function set_language( value ) {
    Cookies.set('LANG', value, {
        expires: new Date('January 1, 2038'),
        path: BUGZILLA.param.cookie_path
    });
    window.location.reload()
}

// This basically duplicates Bugzilla::Util::display_value for code that
// can't go through the template and has to be in JS.
function display_value(field, value) {
    var field_trans = BUGZILLA.value_descs[field];
    if (!field_trans) return value;
    var translated = field_trans[value];
    if (translated) return translated;
    return value;
}

// polyfill .trim
if (!String.prototype.trim) {
    (function() {
        // Make sure we trim BOM and NBSP
        var rtrim = /^[\s\uFEFF\xA0]+|[\s\uFEFF\xA0]+$/g;
        String.prototype.trim = function() {
            return this.replace(rtrim, '');
        };
    })();
}

// html encoding
if (!String.prototype.htmlEncode) {
    (function() {
        String.prototype.htmlEncode = function() {
            return this.replace(/&/g, '&amp;')
                       .replace(/</g, '&lt;')
                       .replace(/>/g, '&gt;')
                       .replace(/"/g, '&quot;');
        };
    })();
}

// our auto-completion disables browser native autocompletion, however this
// excludes it from being restored by bf-cache.  trick the browser into
// restoring by changing the autocomplete attribute when a page is hidden and
// shown.
$().ready(function() {
    $(window).on('pagehide', function() {
        $('.bz_autocomplete').attr('autocomplete', 'on');
    });
    $(window).on('pageshow', function(event) {
        $('.bz_autocomplete').attr('autocomplete', 'off');
    });
});
