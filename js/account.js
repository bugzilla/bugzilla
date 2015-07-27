/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
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
});
