/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {

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

    $('#mfa-enable')
        .click(function(event) {
            event.preventDefault();
            $('#mfa-enable-container').show();
            $(this).hide();
        });

    $('#mfa')
        .change(function(event) {
            var mfa = $(this).val();

            $('.mfa-provider').hide();
            $('#update').attr('disabled', true);
            if (mfa === '') {
                $('#mfa-confirm').hide();
            }
            else {
                $('#mfa-confirm').show();
                $('.mfa-api-blurb').show();
                if (mfa === 'TOTP') {
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
                    .error(function(data) {
                        $('#mfa-totp-throbber').hide();
                        if (data.statusText === 'abort')
                            return;
                        var message = data.responseJSON ? data.responseJSON.message : 'Unexpected Error';
                        console.log(message);
                    });
                }
            }
        })
        .change();

    $('#mfa-disable')
        .click(function(event) {
            event.preventDefault();
            $('#mfa-disable-container').show();
            $('#mfa-confirm').show();
            $('.mfa-api-blurb').hide();
            $('#mfa-password').focus();
            $('#update').attr('disabled', false);
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
        $('#update').attr('disabled', true);
        $(window).on('pageshow', function() {
            $('#mfa').val('').change();
        });
    }
});
