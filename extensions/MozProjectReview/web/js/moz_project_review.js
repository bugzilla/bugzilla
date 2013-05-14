/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

var Dom = YAHOO.util.Dom;
var Event = YAHOO.util.Event;

var MPR = {
    required_fields: {
        "initial_questions": {
            "short_desc": "Please enter a value for project or feature name in the initial questions section",
            "cc": "Please enter a value for points of contact in the initial questions section",
            "key_initiative": "Please select a value for key initiative in the initial questions section",
            "project_status": "Please select a value for project status in the initial questions section",
            "mozilla_data": "Please select a value for mozilla data in the initial questions section",
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
            "legal_priority": "Please select a priority for the legal questions section",
            "legal_help_from_legal": "Please describe the help needed from the Legal department"
        },
        "legal_sow_questions": {
            "legal_sow_vendor_name": "Please enter a value for SOW legal vendor name",
            "legal_sow_vendor_address": "Please enter a value for SOW vendor address",
            "legal_sow_vendor_email": "Please enter a value for SOW vendor email for notices",
            "legal_sow_vendor_mozcontact": "Please enter a value for SOW Mozilla contact",
            "legal_sow_vendor_contact": "Please enter a value for SOW vendor contact and email address",
            "legal_sow_vendor_services": "Please enter a value for SOW vendor services description",
            "legal_sow_vendor_deliverables": "Please enter a value for SOW vendor deliverables description",
            "legal_sow_start_date": "Please enter a value for SOW vendor start date",
            "legal_sow_end_date": "Please enter a value for SOW vendor end date",
            "legal_sow_vendor_payment": "Please enter a value for SOW vendor payment amount",
            "legal_sow_vendor_payment_basis": "Please enter a value for SOW vendor payment basis",
            "legal_sow_vendor_payment_schedule": "Please enter a value for SOW vendor payment schedule",
            "legal_sow_vendor_total_max": "Please enter a value for SOW vendor maximum total to be paid",
            "legal_sow_vendor_product_line": "Please enter a value for SOW vendor product line"
        }
    },

    select_inputs: [
        'key_initiative',
        'project_status',
        'mozilla_data',
        'separate_party',
        'relationship_type',
        'data_access',
        'vendor_cost',
        'po_needed',
        'sec_affects_products',
        'privacy_policy_project',
        'privacy_policy_user_data',
        'privacy_policy_vendor_user_data',
        'privacy_policy_vendor_questionnaire',
        'legal_priority',
        'legal_sow_vendor_product_line',
        'legal_vendor_services_where',
        'finance_purchase_inbudget',
        'finance_purchase_urgency'
    ],

    init: function () {
        // Bind the updateSections function to each of the inputs desired
        for (var i = 0, l = this.select_inputs.length; i < l; i++) {
            Event.on(this.select_inputs[i], 'change', MPR.updateSections);
        }
        MPR.updateSections();
    },

    fieldValue: function (id) {
        var field = Dom.get(id);
        if (!field) return '';
        if (field.type == 'text' 
            || field.type == 'textarea')
        {
            return field.value;
        }
        return field.options[field.selectedIndex].value;
    },

    updateSections: function () {
        // Sections that will be hidden/shown based on the input values
        // Start out as all false except for initial questions which is always visible
        var page_sections = {
            initial_questions: true,
            key_initiative_other_row: false,
            initial_separate_party_questions: false,
            finance_questions: false,
            finance_purchase_notinbudget_why_row: false,
            po_needed_row: false,
            legal_questions: false,
            legal_sow_questions: false,
            legal_vendor_single_country: false,
            legal_vendor_services_where_row: false,
            sec_review_questions: false,
            privacy_policy_project_questions: false,
            privacy_policy_vendor_questions: false,
            privacy_policy_project_link_row: false,
            privacy_policy_project_user_data_bug_row: false,
            privacy_policy_vendor_extra: false
        };

        if (MPR.fieldValue('key_initiative') == 'Other') {
            page_sections.key_initiative_other_row = true;
        }

        if (MPR.fieldValue('mozilla_data') == 'Yes') {
            page_sections.legal_questions = true;
            page_sections.privacy_policy_project_questions = true;
            page_sections.sec_review_questions = true;
        }

        if (MPR.fieldValue('separate_party') == 'Yes') {
            page_sections.initial_separate_party_questions = true;

            if (MPR.fieldValue('relationship_type')
                && MPR.fieldValue('relationship_type') != 'Hardware Purchase')
            {
                page_sections.legal_questions = true;
            }

            if (MPR.fieldValue('relationship_type') == 'Vendor/Services'
                || MPR.fieldValue('relationship_type') == 'Distribution/Bundling')
            {
                page_sections.legal_sow_questions = true;
                page_sections.legal_vendor_services_where_row = true;
            }

            if (MPR.fieldValue('relationship_type') == 'Hardware Purchase') {
                page_sections.finance_questions = true;
            }

            if (MPR.fieldValue('data_access') == 'Yes') {
                page_sections.legal_questions = true;
                page_sections.sec_review_questions = true;
                page_sections.privacy_policy_vendor_questions = true;
            }

            if (MPR.fieldValue('vendor_cost') == '<= $25,000') {
                page_sections.po_needed_row = true;
            }

            if (MPR.fieldValue('po_needed') == 'Yes') {
                page_sections.finance_questions = true;
            }

            if (MPR.fieldValue('vendor_cost') == '> $25,000') {
                page_sections.finance_questions = true;
            }
        }

        if (MPR.fieldValue('legal_vendor_services_where') == 'A single country') {
            page_sections.legal_vendor_single_country = true;
        }

        if (MPR.fieldValue('finance_purchase_inbudget') == 'No') {
            page_sections.finance_purchase_notinbudget_why_row = true;
        }

        if (MPR.fieldValue('privacy_policy_project') == 'Yes') {
            page_sections.privacy_policy_project_link_row = true;
        }

        if (MPR.fieldValue('privacy_policy_user_data') == 'Yes') {
            page_sections.privacy_policy_project_user_data_bug_row = true;
        }

        if (MPR.fieldValue('privacy_policy_vendor_user_data') == 'Yes') {
            page_sections.privacy_policy_vendor_extra = true;
        }

        // Toggle the individual page_sections
        for (section in page_sections) {
            MPR.toggleShowSection(section, page_sections[section]);
        }
    },

    toggleShowSection: function (section, show) {
        if (show) {
            Dom.removeClass(section, 'bz_default_hidden');
        }
        else { 
            Dom.addClass(section ,'bz_default_hidden');
        }
    },

    validateAndSubmit: function () {
        var alert_text = '';
        var section = '';
        for (section in this.required_fields) {
            if (!Dom.hasClass(section, 'bz_default_hidden')) {
                var field = '';
                for (field in MPR.required_fields[section]) {
                    if (!MPR.isFilledOut(field)) {
                        alert_text += this.required_fields[section][field] + "\n";
                    }
                }
            }
        }
 
        // Special case checks
        if (MPR.fieldValue('relationship_type') == 'Vendor/Services'
            && MPR.fieldValue('legal_vendor_services_where') == '')
        {
            alert_text += "Please select a value for vendor services where\n";
        }

        if (MPR.fieldValue('relationship_type') == 'Vendor/Services'
            && MPR.fieldValue('legal_vendor_services_where') == 'A single country'
            && MPR.fieldValue('legal_vendor_single_country') == '')
        {
            alert_text += "Please select a value for vendor services where single country\n";
        }

        if (MPR.fieldValue('key_initiative') == 'Other') {
            if (!MPR.isFilledOut('key_initiative_other')) {
                alert_text += "Please enter a value for key initiative in the initial questions section\n";
            }
        }

        if (MPR.fieldValue('separate_party') == 'Yes') {
            if (!MPR.isFilledOut('relationship_type')) {
                alert_text += "Please select a value for type of relationship\n";
            }
            if (!MPR.isFilledOut('data_access')) {
                alert_text += "Please select a value for data access\n";
            }
            if (!MPR.isFilledOut('vendor_cost')) {
                alert_text += "Please select a value for vendor cost\n";
            }
        }

        if (MPR.fieldValue('finance_purchase_inbudget') == 'No') {
            if (!MPR.isFilledOut('finance_purchase_notinbudget_why')) {
                alert_text += "Please include additional description for the out of budget line item\n";
            }
        }

        if (MPR.fieldValue('vendor_cost') == '<= $25,000'
            && MPR.fieldValue('po_needed') == '')
        {
            alert_text += "Please select whether a PO is needed or not\n";
        }

        if (alert_text) {
            alert(alert_text);
            return false;
        }

        return true;
    },

    //Takes a DOM element id and makes sure that it is filled out
    isFilledOut: function (elem_id)  {
        var str = MPR.fieldValue(elem_id);
        return str.length > 0 ? true : false;
    }
};

Event.onDOMReady(function () {
    MPR.init();
});
