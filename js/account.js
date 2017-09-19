/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {

    function make_password_confirm($password1, $password2) {
        return function (event) {
            if ($password1.val() != $password2.val()) {
                $password2.get(0).setCustomValidity("Does not match previous password");
            }
            else {
                $password2.get(0).setCustomValidity("");
            }
        };
    }
    var password1_sel, password2_sel;
    var page       = $("#password-features").data("password-page");
    var check_password_confirm;

    if (page == "account") {
        $("#new_password1, #new_password2, #new_login_name").change(function() {
            $("#old_password").attr("required", true);
        });
    }

    if (page == "confirm") {
        password1_sel = "#passwd1";
        password2_sel = "#passwd2";
    }
    else {
        password1_sel = "#new_password1";
        password2_sel = "#new_password2";
    }

    check_password_confirm  = make_password_confirm($(password1_sel), $(password2_sel));

    $(password1_sel).on("blur", check_password_confirm);
    $(password1_sel).on("change", check_password_confirm);
    $(password2_sel).on("input", check_password_confirm);

    // account disabling

    $('#account-disable-toggle')
        .click(function(event) {
            event.preventDefault();
            var that = $(this);

            if (that.data('open')) {
                $('#account-disable-spinner').html('&#9656;');
                $('#account-disable').hide();
                that.data('open', false);
            }
            else {
                $('#account-disable-spinner').html('&#9662;');
                $('#account-disable').show();
                that.data('open', true);
            }
        });

    $('#account-disable-confirm')
        .click(function(event) {
            $('#account-disable-button').prop('disabled', !$(this).is(':checked'));
        })
        .prop('checked', false);

    $('#account-disable-button')
        .click(function(event) {
            $('#account_disable').val('1');
            document.userprefsform.submit();
        });

    $(window).on('pageshow', function() {
        $('#account_disable').val('');
    });

    // forgot password

    $('#forgot-password')
        .click(function(event) {
            event.preventDefault();
            $('#forgot-form').submit();
        });

    // mfa

    $('#mfa-select-totp')
        .click(function(event) {
            event.preventDefault();
            $('#mfa').val('TOTP');

            $('#mfa-select').hide();
            $('#update').attr('disabled', true);
            $('#mfa-totp-enable-code').attr('required', true);
            $('#mfa-confirm').show();
            $('.mfa-api-blurb').show();
            $('#mfa-enable-shared').show();
            $('#mfa-enable-totp').show();
            $('#mfa-totp-throbber').show();
            $('#mfa-totp-issued').hide();

            var url = 'rest/user/mfa/totp/enroll' +
                '?Bugzilla_api_token=' + encodeURIComponent(BUGZILLA.api_token);
            $.ajax({
                "url": url,
                "contentType": "application/json",
                "processData": false
            })
            .done(function(data) {
                $('#mfa-totp-throbber').hide();
                var iframe = $('#mfa-enable-totp-frame').contents();
                iframe.find('#qr').attr('src', 'data:image/png;base64,' + data.png);
                iframe.find('#secret').text(data.secret32);
                $('#mfa-totp-issued').show();
                $('#mfa-password').focus();
                $('#update').attr('disabled', false);
            })
            .fail(function(data) {
                $('#mfa-totp-throbber').hide();
                if (data.statusText === 'abort')
                    return;
                var message = data.responseJSON ? data.responseJSON.message : 'Unexpected Error';
                console.log(message);
            });
        });

    $('#mfa-select-duo')
        .click(function(event) {
            event.preventDefault();
            $('#mfa').val('Duo');

            $('#mfa-select').hide();
            $('#update').attr('disabled', false);
            $('#mfa-duo-user').attr('required', true);
            $('#mfa-confirm').show();
            $('.mfa-api-blurb').show();
            $('#mfa-enable-shared').show();
            $('#mfa-enable-duo').show();
            $('#mfa-password').focus();
        });

    $('#mfa-disable')
        .click(function(event) {
            event.preventDefault();
            $('.mfa-api-blurb, .mfa-buttons').hide();
            $('#mfa-disable-container, #mfa-auth-container').show();
            $('#mfa-confirm').show();
            $('#mfa-password').focus();
            $('#update').attr('disabled', false);
            $('.mfa-protected').hide();
            $(this).hide();
        });

    $('#mfa-recovery')
        .click(function(event) {
            event.preventDefault();
            $('.mfa-api-blurb, .mfa-buttons').hide();
            $('#mfa-recovery-container, #mfa-auth-container').show();
            $('#mfa-password').focus();
            $('#update').attr('disabled', false).val('Generate Printable Recovery Codes');
            $('#mfa-action').val('recovery');
            $(this).hide();
        });

    var totp_popup;
    $('#mfa-totp-apps, #mfa-totp-text')
        .click(function(event) {
            event.preventDefault();
            totp_popup = $('#' + $(this).attr('id') + '-popup').bPopup({
                speed: 100,
                followSpeed: 100,
                modalColor: '#444'
            });
        });
    $('.mfa-totp-popup-close')
        .click(function(event) {
            event.preventDefault();
            totp_popup.close();
        });

    if ($('#mfa-action').length) {
        if ($("#mfa-action").data('nopassword')) {
            $('#update')
                .attr('disabled', false)
                .val("Reset Password")
                .click(function(event) {
                    event.preventDefault();
                    $('#forgot-form').submit();
                });
        }
        else {
            $("#update").attr('disabled', true);
        }
    }

    // api-key

    $('#apikey-toggle-revoked')
        .click(function(event) {
            event.preventDefault();
            $('.apikey_revoked.bz_tui_hidden').removeClass('bz_tui_hidden');
            if ($('.apikey_revoked').is(':visible')) {
                $('.apikey_revoked').hide();
                $(this).text('Show Revoked Keys');
            }
            else {
                $('.apikey_revoked').show();
                $(this).text('Hide Revoked Keys');
            }
        });

    $('#new_key')
        .change(function(event) {
            if ($(this).is(':checked')) {
                $('#new_description').focus();
            }
        });
});
