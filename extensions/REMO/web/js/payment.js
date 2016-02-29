/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var bug_cache = {};

function validateAndSubmit() {
    var alert_text = '';
    if(!isFilledOut('firstname')) alert_text += "Please enter your first name\n";
    if(!isFilledOut('lastname')) alert_text += "Please enter your last name\n";
    if(!isFilledOut('wikiprofile')) alert_text += "Please enter a wiki user profile.\n";
    if(!isFilledOut('wikipage')) alert_text += "Please enter a wiki page address.\n";
    if(!isFilledOut('bug_id')) alert_text += "Please enter a valid bug id to attach this additional information to.\n";
    if(!isFilledOut('expenseform')) alert_text += "Please enter an expense form to upload.\n";
    if(!isFilledOut('receipts')) alert_text += "Please enter a receipts file to upload.\n";

    if (alert_text) {
        alert(alert_text);
        return false;
    }

    return true;
}

function getBugInfo (evt) {
    var bug_id = parseInt(this.value);
    var div = $("#bug_info");

    if (!bug_id) {
        div.text("");
        return true;
    }
    div.show();

    if (bug_cache[bug_id]) {
        div.text(bug_cache[bug_id]);
        return true;
    }

    div.text('Getting bug info...');

    var url = ("rest/bug/" + bug_id +
               "?include_fields=product,component,status,summary&Bugzilla_api_token=" + BUGZILLA.api_token);
    $.getJSON(url).done(function(data) {
        var bug_message = "";
        if (data) {
            if (data.bugs[0].product !== 'Mozilla Reps'
                || data.bugs[0].component !== 'Budget Requests')
            {
                bug_message = "You can only attach budget payment " +
                    "information to bugs under the product " +
                    "'Mozilla Reps' and component 'Budget Requests'.";
            }
            else {
                bug_message = "Bug " + bug_id + " - " + data.bugs[0].status +
                    " - " + data.bugs[0].summary;
            }
        }
        else {
            bug_message = "Get bug failed: " + data.responseText;
        }
        div.text(bug_message);
        bug_cache[bug_id] = bug_message;
    }).fail(function(res, x, y) {
        if (res.responseJSON && res.responseJSON.error) {
            div.text(res.responseJSON.message);
        }
    });
    return true;
}

$(document).ready(function () {
    $("#bug_id").blur(getBugInfo);
    $("#receivedpayment").change(function() {
        if (!$('#receivedpayment').is(':checked')) {
            $('#paymentinfo').show();
        }
        else {
            $('#paymentinfo').hide();
        }
    });
});
