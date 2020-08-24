/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(document).ready(function() {
    'use strict';

    var first_time = $("#first_time");
    first_time.change(function(evt) {
        if (this.value !== 'Yes') {
            $("#prior_bug").show();
            $("#prior_bug label").addClass("required");
        }
        else {
            $("#prior_bug").hide();
            $("#prior_bug label").removeClass("required");
        }
    }).change();

    $("#age").change(function(evt) {
        if (this.value === 'Yes') {
            $('#age_warning').hide();
            $('#submit').prop("disabled", false);
        }
        else {
            $('#age_warning').show();
            $('#submit').prop("disabled", true);
        }
    }).change();

    $("#pmo_account").change(function(evt) {
        if (this.value === 'Yes') {
            $('#pmo_warning').hide();
            $('#submit').prop("disabled", false);
        }
        else {
            $('#pmo_warning').show();
            $('#submit').prop("disabled", true);
        }
    }).change();

    $("#information").change(function(evt) {
        if (this.value === 'Yes') {
            $('#information_warning').hide();
            $('#submit').prop("disabled", false);
        }
        else {
            $('#information_warning').show();
            $('#submit').prop("disabled", true);
        }
    }).change();

    $("#privacy").change(function(evt) {
        if (this.checked) {
            $('#submit').prop("disabled", false);
        }
        else {
            $('#submit').prop("disabled", true);
        }
    }).change();

    $('#tmRequestForm').submit(function (event) {
        var mozillian_re = /^https?:\/\/people.mozilla.org\/([^\/]+\/)?p\/[^\/]+\/?$/i;
        var errors = [];
        var missing = false;

        $('label.required').each(function (index) {
            var id = $(this).attr("for");
            var input = $("#" + id);
            var value = input.val().trim();

            if (id == 'mozillian') {
                if (!value.match(mozillian_re)) {
                    input.addClass("missing");
                    errors.push("The people.mozilla.org Profile URL is invalid");
                    event.preventDefault();
                }
                else {
                    input.removeClass("missing");
                }
            }
            else {
                if (value == "") {
                    input.addClass("missing");
                    missing = true;
                    event.preventDefault();
                }
                else {
                    input.removeClass("missing");
                }
            }
        });

        if (missing) {
            errors.push("There are missing required fields");
        }

        if (errors.length) {
            alert(errors.join("\n"));
        }

        $('#short_desc').val(
            "Application Form: " + $('#first_name').val() + ' ' + $('#last_name').val()
        );
    });
});
