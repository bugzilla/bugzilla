/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

YAHOO.namespace('MozProjectReview');

var MPR = YAHOO.MozProjectReview;
var Dom = YAHOO.util.Dom;

MPR.required_fields = {
    "initial_questions": {
        "short_desc": "Please enter a value for project or feature name in the initial questions section",
        "cc": "Please enter a value for points of contact in the initial questions section",
        "urgency": "Please enter a value for urgency in the initial questions section",
        "key_initiative": "Please select a value for key initiative in the initial questions section",
        "project_status": "Please select a value for project status in the initial questions section",
        "mozilla_data": "Please select a value for mozilla data in the initial questions section",
        "new_or_change": "Please select a value for new or change to existing project in the initial questions section",
        "separate_party": "Please select a value for separate party in the initial questions section"
    },
    "finance_questions": {
        "finance_purchase_vendor": "Please enter a value for vendor in the finance questions section",
        "finance_purchase_what": "Please enter a value for what in the finance questions section",
        "finance_purchase_why": "Please enter a value for why in the finance questions section",
        "finance_purchase_risk": "Please enter a value for risk in the finance questions section",
        "finance_purchase_alternative": "Please enter a value for alternative in the finance questions section",
        "finance_purchase_inbudget": "Please enter a value for in budget in the finance questions section",
        "finance_purchase_urgency": "Please select a value for urgency in the finance questions section",
        "finance_purchase_cost": "Please enter a value for total cost in the finance questions section"
    },
    "legal_questions": {
        "legal_priority": "Please select a priority for the legal questions section"
    }
};

MPR.toggleSpecialSections = function () {
    var mozilla_data_select = Dom.get('mozilla_data');
    var data_access_select  = Dom.get('data_access');
    var vendor_cost_select  = Dom.get('vendor_cost');

    if (mozilla_data_select.value == 'Yes') {
        Dom.removeClass('legal_questions', 'bz_default_hidden');
        Dom.removeClass('privacy_policy_project_questions', 'bz_default_hidden');
        Dom.removeClass('data_safety_questions', 'bz_default_hidden');
        Dom.removeClass('sec_review_questions', 'bz_default_hidden');
    }
    else {
        Dom.addClass('legal_questions', 'bz_default_hidden');
        Dom.addClass('privacy_policy_project_questions', 'bz_default_hidden');
        Dom.addClass('data_safety_questions', 'bz_default_hidden');
        Dom.addClass('sec_review_questions', 'bz_default_hidden');
    }

    if (data_access_select.value == 'Yes' || mozilla_data_select.value == 'Yes') {
        Dom.removeClass('sec_review_questions', 'bz_default_hidden');
    }
    else {
        Dom.addClass('sec_review_questions', 'bz_default_hidden');
    }

    if (data_access_select.value == 'Yes') {
        Dom.removeClass('privacy_policy_vendor_questions', 'bz_default_hidden');
    }
    else {
        Dom.addClass('privacy_policy_vendor_questions', 'bz_default_hidden');
    }

    if (vendor_cost_select.value == '> $25,000') {
        Dom.removeClass('finance_questions', 'bz_default_hidden');
    }
    else {
        Dom.addClass('finance_questions', 'bz_default_hidden');
    }
}

MPR.toggleVisibleById = function () {
    var args   = Array.prototype.slice.call(arguments);
    var select = args.shift();
    var value  = args.shift();
    var ids    = args;

    if (typeof select == 'string') {
        select = Dom.get(select);
    }

    for (var i = 0; i < ids.length; i++) {
        if (select.value == value) {
            Dom.removeClass(ids[i], 'bz_default_hidden');
        }
        else {
            Dom.addClass(ids[i], 'bz_default_hidden');
        }
    }
}

MPR.validateAndSubmit = function () {
    var alert_text = '';
    var section = '';
    for (section in MPR.required_fields) {
        if (!Dom.hasClass(section, 'bz_default_hidden')) {
            var field = '';
            for (field in MPR.required_fields[section]) {
                if (!MPR.isFilledOut(field)) {
                    alert_text += MPR.required_fields[section][field] + "\n";
                }
            }
        }
    }

    if (Dom.get('key_initiative').value == 'Other') {
        if (!MPR.isFilledOut('key_initiative_other'))
            alert_text += "Please enter a value for key initiative in the initial questions section\n";
    }

    if (Dom.get('separate_party').value == 'Yes') {
        if (!MPR.isFilledOut('relationship_type')) alert_text += "Please select a value for type of relationship\n";
        if (!MPR.isFilledOut('data_access')) alert_text += "Please select a value for data access\n";
        if (!MPR.isFilledOut('vendor_cost')) alert_text += "Please select a value for vendor cost\n";
    }

    if (Dom.get('finance_purchase_inbudget').value == 'No') {
        if (!MPR.isFilledOut('finance_purchase_notinbudget_why')) 
            alert_text += "Please include additional description for the out of budget line item\n";
    }

    if (alert_text) {
        alert(alert_text);
        return false;
    }

    return true;
}

YAHOO.util.Event.onDOMReady(function() {
    MPR.toggleSpecialSections();
    MPR.toggleVisibleById('new_or_change', 'Existing', 'mozilla_project_row');
    MPR.toggleVisibleById('separate_party', 'Yes', 'initial_separate_party_questions');
    MPR.toggleVisibleById('relationship_type', 'Vendor/Services', 'legal_sow_details_row');
    MPR.toggleVisibleById('vendor_cost', '> $25,000', 'finance_questions');
    MPR.toggleVisibleById('privacy_policy_project', 'Yes', 'privacy_policy_project_link_row');
    MPR.toggleVisibleById('privacy_policy_user_data', 'Yes', 'privacy_policy_project_user_data_bug_row');
    MPR.toggleVisibleById('privacy_policy_vendor_user_data', 'Yes', 'privacy_policy_vendor_extra');
    MPR.toggleVisibleById('data_safety_user_data', 'Yes', 'data_safety_extra_questions');
    MPR.toggleVisibleById('data_safety_retention', 'Yes', 'data_safety_retention_length_row');
    MPR.toggleVisibleById('data_safety_separate_party', 'Yes', 'data_safety_separate_party_data_row');
    MPR.toggleVisibleById('data_safety_community_visibility', 'Yes', 'data_safety_communication_channels_row');
    MPR.toggleVisibleById('data_safety_community_visibility', 'No', 'data_safety_communication_plan_row');
});

//Takes a DOM element id and makes sure that it is filled out
MPR.isFilledOut = function (elem_id)  {
    var str = Dom.get(elem_id).value;
    return str.length > 0 ? true : false;
}
