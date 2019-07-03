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

async function getBugInfo (evt) {
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

    try {
        const { bugs } = await Bugzilla.API.get(`bug/${bug_id}?`, {
            include_fields: ['product', 'component', 'status', 'summary'],
        });
        const { product, component, status, summary } = bugs[0];
        const bug_message = (product !== 'Mozilla Reps' || component !== 'Budget Requests') ?
            "You can only attach budget payment information to bugs under \
                the product 'Mozilla Reps' and component 'Budget Requests'." :
            `Bug ${bug_id} - ${status} - ${summary}`;

        div.text(bug_message);
        bug_cache[bug_id] = bug_message;
    } catch ({ message }) {
        div.text(`Get bug failed: ${message}`);
    }

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
