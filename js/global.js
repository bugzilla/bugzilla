/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

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

function set_language( value ) {
    $.cookie('LANG', value, {
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
