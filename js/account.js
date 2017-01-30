/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {

    function make_password_strength($password) {
        return function(event) {
            var password = $password.val();
            var missing_features = {"upper": true, "lower": true, "numbers": true, "symbols": true, "length12": true};
            var features = [],
                charset = 0,
                score = 0,
                min_features = 3;

            $("#password-meter").show();
            $("#password-meter-label").show();

            if (password.match(/[A-Z]/)) {
                delete missing_features.upper;
                features.push("upper");
                charset += 26;
            }
            if (password.match(/[a-z]/)) {
                delete missing_features.lower;
                features.push("lower");
                charset += 26;
            }
            if (password.match(/[0-9]/)) {
                delete missing_features.numbers;
                features.push("numbers");
                charset += 10;
            }
            if (password.match(/[^A-Za-z0-9]/)) {
                delete missing_features.symbols;
                features.push("symbols");
                charset += 30; // there are 30-32 typable characters on a keyboard.
            }
            if (password.length > 12) {
                delete missing_features.length12;
                features.push("length12");
            }

            $("#password-features li").removeClass("feature-ok");
            features.forEach(function(name) {
                $("#password-feature-" + name).addClass("feature-ok");
            });

            var entropy = Math.floor(Math.log(charset) * (password.length / Math.log(2)));
            if (entropy) {
                score = entropy/128;
            }

            $password.get(0).setCustomValidity("");
            if (features.length < min_features) {
                $("#password-msg")
                    .text("Password does not meet requirements")
                    .attr("class", "password-bad");
                $password.get(0).setCustomValidity($("#password-msg").text());
            }
            else if (password.length < 8) {
                $("#password-msg")
                    .text("Password is too short")
                    .attr("class", "password-bad");
                $password.get(0).setCustomValidity($("#password-msg").text());
            }
            else {
                $("#password-msg")
                    .text("Password meets requirements")
                    .attr("class", "password-good");
                $password.get(0).setCustomValidity("");
            }

            if (entropy < 60) {
                $("#password-meter")
                    .removeClass("meter-good meter-ok")
                    .addClass("meter-bad");
            }
            else if (entropy >= 120) {
                $("#password-meter")
                    .removeClass("meter-bad meter-ok")
                    .addClass("meter-good");
            }
            else if (entropy > 60) {
                $("#password-meter")
                    .removeClass("meter-bad meter-good")
                    .addClass("meter-ok");
            }

            if (score === 0) {
                score = 0.01;
                $("#password-meter")
                    .removeClass("meter-good meter-ok")
                    .addClass("meter-bad");
            }

            $("#password-meter").width(Math.max(0, Math.min($password.width()+10, Math.ceil(($password.width()+10) * score))));
        };
    }

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
    var complexity = $("#password-features").data("password-complexity");
    var page       = $("#password-features").data("password-page");
    var check_password_strength, check_password_confirm;

    if (page == "account") {
        $("#new_password1, #new_password2, #new_login_name").change(function() {
            $("#old_password").attr("required", true);
        });
    }

    if (complexity == "bmo") {
        if (page == "confirm") {
            password1_sel = "#passwd1";
            password2_sel = "#passwd2";
        }
        else {
            password1_sel = "#new_password1";
            password2_sel = "#new_password2";
        }
        $("#password-features").show();

        check_password_strength = make_password_strength($(password1_sel));
        check_password_confirm  = make_password_confirm($(password1_sel), $(password2_sel));

        $(password1_sel).on("input", check_password_strength);
        $(password1_sel).on("focus", check_password_strength);

        $(password1_sel).on("blur", check_password_confirm);
        $(password1_sel).on("change", check_password_confirm);
        $(password2_sel).on("input", check_password_confirm);
    }
    else {
        $("#password-features").hide();
    }

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
        $('#update').attr('disabled', true);
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
