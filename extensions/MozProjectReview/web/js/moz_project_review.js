/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

$(function() {
    'use strict';
    var required_fields = {
        "initial_questions": {
            "comment": "Please enter a value for description in the initial questions section.",
            "key_initiative": "Please select a value for key initiative in the initial questions section.",
            "contract_type": "Please select a value for contract type in the initial questions section.",
            "mozilla_data": "Please select a value for mozilla data in the initial questions section.",
            "vendor_cost": "Please select a value for vendor cost in the initial questions section.",
            "timeframe": "Please select a value for timeframe in the initial questions section.",
            "contract_priority": "Please select a value for priority in the initial questions section.",
            "internal_org": "Please select a value for the internal organization in the initial questions section."
        },
        "key_initiative_other": {
            "key_initiative_other": "Please enter a value for other key initiative in the initial questions section."
        },
        "mozilla_data_explain_row": {
            "mozilla_data_explain": "Please enter a value for mozilla data access explanation in the initial questions section."
        },
        "contract_type_other": {
            "contract_type_other": "Please enter a value for other contract type in the initial questions section."
        },
        "contract_specific_questions": {
            "other_party": "Please enter a value for vendor name in the contract specific questions.",
            "vendor_services_where": "Please enter a value for the where the services will be provided in the contract specific questions.",
        },
        "independent_contractor_questions": {
            "independent_contractor_prev_work": "Please select a value for previous work in the independent contractor section.",
            "independent_contractor_incorporated": "Please select a value for incorporated in the independent contractor section.",
            "independent_contractor_staff_agency": "Please select a value for staffing agency in the independent contractor section.",
            "independent_contractor_other_clients": "Please select a value for other clients in the independent contractor section.",
            "independent_contractor_dupe_services": "Please select a value for in the independent contractor section.",
            "independent_contractor_self_manage": "Please select a value for self management of time in the independent contractor section.",
            "independent_contractor_own_equipment": "Please select a value for use of contractors own equipment in the independent contractor section.",
            "independent_contractor_mozilla_facility": "Please select a value for use of Mozilla facility in the independent contractor section.",
            "independent_contractor_supervising": "Please select a value for contractor supervising Mozilla employees in the independent contractor section.",
        },
        "independent_contractor_prev_work_bug_row": {
            "independent_contractor_prev_work_bug": "Please enter a value for previous work bug id in the independent contractor section."
        },
        "independent_contractor_dupe_services_temp_row": {
            "independent_contractor_dupe_services_temp": "Please select a value for temporarily need duplicate services in the independent contractor section."
        },
        "sow_details": {
            "sow_vendor_address": "Please enter a value for SOW vendor address.",
            "sow_vendor_email": "Please enter a value for SOW vendor email for notices.",
            "sow_vendor_contact": "Please enter a value for SOW vendor contact and email address.",
            "sow_vendor_services": "Please enter a value for SOW vendor services description.",
            "sow_vendor_deliverables": "Please enter a value for SOW vendor deliverables description.",
            "sow_start_date": "Please enter a value for SOW vendor start date.",
            "sow_end_date": "Please enter a value for SOW vendor end date.",
            "sow_vendor_payment": "Please enter a value for SOW vendor payment amount.",
            "sow_vendor_payment_basis": "Please enter a value for SOW vendor payment basis.",
            "sow_vendor_cap_expenses": "Please enter a value for SOW cap on reimbursable expenses.",
            "sow_vendor_payment_schedule": "Please enter a value for SOW vendor payment schedule.",
            "sow_vendor_total_max": "Please enter a value for SOW vendor maximum total to be paid.",
        },
        "sow_vendor_mozilla_systems_explain_row": {
            "sow_vendor_mozilla_systems_explain": "Please enter a value for SOW vendor explanation for use of mozilla systems."
        },
        "sow_vendor_onsite_where_row": {
            "sow_vendor_onsite_where": "Please enter a value for SOW vendor onsite where and when."
        },
        "finance_questions": {
            "finance_purchase_inbudget": "Please enter a value for in budget in the finance questions section.",
            "finance_purchase_what": "Please enter a value for what in the finance questions section.",
            "finance_purchase_why": "Please enter a value for why in the finance questions section.",
            "finance_purchase_risk": "Please enter a value for risk in the finance questions section.",
            "finance_purchase_alternative": "Please enter a value for alternative in the finance questions section.",
        },
        "total_cost_row": {
            "total_cost": "Please enter a value for total cost"
        }
    };

    var select_inputs = [
        'contract_type',
        'independent_contractor_prev_work',
        'independent_contractor_dupe_services',
        'key_initiative',
        'mozilla_data',
        'vendor_cost',
        'sow_vendor_mozilla_systems',
        'sow_vendor_onsite'
    ];

    function init() {
        // Bind the updateSections function to each of the inputs desired
        for (var i = 0, l = select_inputs.length; i < l; i++) {
            $('#' + select_inputs[i]).change(updateSections);
        }
        updateSections();
        $('#mozProjectForm').submit(validateAndSubmit);
    }

    function updateSections(e) {
        if ($('#key_initiative').val() == 'Other') {
            $('#key_initiative_other').show();
            if ($(e.target).attr('id') == 'key_initiative') $('#key_initiative_other').focus();
        } else {
            $('#key_initiative_other').hide();
        }

        if ($('#vendor_cost').val() == '< $25,000 PO Needed'
            || $('#vendor_cost').val() == '> $25,000')
        {
            $('#finance_questions').show();
        } else {
            $('#finance_questions').hide();
        }

        var do_sec_review = [
            'Engaging a new vendor company',
            'Adding a new SOW with a vendor',
            'Extending a SOW or renewing a contract',
            'Purchasing software',
            'Signing up for an online service',
            'Other'
        ];
        var contract_type = $('#contract_type').val();
        if ((contract_type && $.inArray(contract_type, do_sec_review) >= 0)
            || $('#mozilla_data').val() == 'Yes')
        {
            $('#sec_review_questions').show();

        } else {
            $('#sec_review_questions').hide();
        }

        if ($('#mozilla_data').val() == 'Yes') {
            $('#mozilla_data_explain_row').show();
            if ($(e.target).attr('id') == 'mozilla_data') $('#mozilla_data_explain').focus();

        } else {
            $('#mozilla_data_explain_row').hide();
        }

        if (contract_type == 'Other') {
            $('#contract_type_other').show();
            if ($(e.target).attr('id') == 'contract_type') $('#contract_type_other').focus();
        }
        else {
            $('#contract_type_other').hide();
        }

        if (contract_type == 'Engaging a new vendor company'
            || contract_type == 'Engaging an individual (independent contractor, temp agency worker, incorporated)'
            || contract_type == 'Adding a new SOW with a vendor')
        {
            $('#sow_details').show();
        }
        else {
            $('#sow_details').hide();
        }

        if (contract_type == "Extending a SOW or renewing a contract"
            || contract_type == "Purchasing software"
            || contract_type == "Purchasing hardware"
            || contract_type == "Signing up for an online service"
            || contract_type == "Other")
        {
            $('#total_cost_row').show();
        }
        else {
            $('#total_cost_row').hide();
        }

        if (contract_type == 'Engaging an individual (independent contractor, temp agency worker, incorporated)') {
            $('#independent_contractor_questions').show();
        }
        else {
           $('#independent_contractor_questions').hide();
        }

        if ($('#independent_contractor_prev_work').val() == 'Yes') {
            $('#independent_contractor_prev_work_bug_row').show();
            if ($(e.target).attr('id') == 'independent_contractor_prev_work')
                $('#independent_contractor_prev_work_bug').focus();
        }
        else {
            $('#independent_contractor_prev_work_bug_row').hide();
        }

        if ($('#independent_contractor_dupe_services').val() == 'Yes') {
            $('#independent_contractor_dupe_services_temp_row').show();
            if ($(e.target).attr('id') == 'independent_contractor_dupe_services')
                $('#independent_contractor_dupe_services_temp').focus();
        }
        else {
            $('#independent_contractor_dupe_services_temp_row').hide();
        }

        if ($('#sow_vendor_mozilla_systems').val() == 'Yes') {
            $('#sow_vendor_mozilla_systems_explain_row').show();
            if ($(e.target).attr('id') == 'sow_vendor_mozilla_systems')
                $('#sow_vendor_mozilla_systems_explain').focus();
        }
        else {
            $('#sow_vendor_mozilla_systems_explain_row').hide();
        }

        if ($('#sow_vendor_onsite').val() == 'Yes') {
            $('#sow_vendor_onsite_where_row').show();
            if ($(e.target).attr('id') == 'sow_vendor_onsite')
                $('#sow_vendor_onsite_where').focus();
        }
        else {
            $('#sow_vendor_onsite_where_row').hide();
        }
    }

    function validateAndSubmit(e) {
        var alert_text = '',
            section    = '',
            field      = '';
        for (section in required_fields) {
            if ($('#' + section).is(':visible')) {
                for (field in required_fields[section]) {
                    if (!isFilledOut(field)) {
                        alert_text += required_fields[section][field] + "\n";
                    }
                }
            }
        }

        if (alert_text) {
            alert(alert_text);
            return false;
        }

        $('#short_desc').val('Legal Review: Contract for ' +
                             $('#contract_type').val() +
                             ' with ' +
                             $('#other_party').val());

        var component_map = {
            "Engaging a new vendor company": "Vendor/Services",
            "Adding a new SOW with a vendor": "Vendor/Services",
            "Extending a SOW or renewing a contract": "Vendor/Services",
            "Purchasing hardware": "Vendor/Services",
            "Other": "Vendor/Services",
            "Engaging an individual (independent contractor, temp agency worker, incorporated)": "Independent Contractor Agreement",
            "An agreement with a partner": "Firefox Distribution or Other Partner Agreement",
            "Purchasing software": "License Review",
            "Signing up for an online service" : "License Review"
        }

        var contract_type = $('#contract_type').val();
        if (component_map[contract_type]) {
            $('#component').val(component_map[contract_type]);
        }

        return true;
    }

    //Takes a DOM element id and makes sure that it is filled out
    function isFilledOut(id)  {
        if (!id) return false;
        var str = $('#' + id).val();
        if (!str || str.length == 0) return false;
        return true;
    }

    // date pickers
    $('.date-field').datetimepicker({
        format: 'Y-m-d',
        datepicker: true,
        timepicker: false,
        scrollInput: false,
        lazyInit: false,
        closeOnDateSelect: true
    });
    $('.date-field-img')
        .click(function(event) {
            var id = $(event.target).attr('id').replace(/-img$/, '');
            $('#' + id).datetimepicker('show');
        })

    init();
});
