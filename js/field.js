/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

/* This library assumes that the needed YUI libraries have been loaded 
   already. */

var bz_no_validate_enter_bug = false;
function validateEnterBug(theform) {
    // This is for the "Make Template" button.
    if (bz_no_validate_enter_bug) {
        // Set it back to false for people who hit the "back" button
        bz_no_validate_enter_bug = false;
        return true;
    }

    var component = theform.component;
    var short_desc = theform.short_desc;
    var version = theform.version;
    var bug_status = theform.bug_status;
    var description = theform.comment;
    var attach_data = theform.data;
    var attach_desc = theform.description;

    var current_errors = YAHOO.util.Dom.getElementsByClassName(
        'validation_error_text', null, theform);
    for (var i = 0; i < current_errors.length; i++) {
        current_errors[i].parentNode.removeChild(current_errors[i]);
    }
    var current_error_fields = YAHOO.util.Dom.getElementsByClassName(
        'validation_error_field', null, theform);
    for (var i = 0; i < current_error_fields.length; i++) {
        var field = current_error_fields[i];
        YAHOO.util.Dom.removeClass(field, 'validation_error_field');
    }

    var focus_me;

    // These are checked in the reverse order that they appear on the page,
    // so that the one closest to the top of the form will be focused.
    if (attach_data && attach_data.value && YAHOO.lang.trim(attach_desc.value) == '') {
        _errorFor(attach_desc, 'attach_desc');
        focus_me = attach_desc;
    }
    // bug_status can be undefined if the bug_status field is not editable by
    // the currently logged in user.
    if (bug_status) {
        var check_description = status_comment_required[bug_status.value];
        if (check_description && YAHOO.lang.trim(description.value) == '') {
            _errorFor(description, 'description');
            focus_me = description;
        }
    }
    if (YAHOO.lang.trim(short_desc.value) == '') {
        _errorFor(short_desc);
        focus_me = short_desc;
    }
    if (version.selectedIndex < 0) {
        _errorFor(version);
        focus_me = version;
    }
    if (component.selectedIndex < 0) {
        _errorFor(component);
        focus_me = component;
    }

    if (focus_me) {
        focus_me.focus();
        return false;
    }

    return true;
}

function _errorFor(field, name) {
    if (!name) name = field.id;
    var string_name = name + '_required';
    var error_text = BUGZILLA.string[string_name];
    var new_node = document.createElement('div');
    YAHOO.util.Dom.addClass(new_node, 'validation_error_text');
    new_node.innerHTML = error_text;
    YAHOO.util.Dom.insertAfter(new_node, field);
    YAHOO.util.Dom.addClass(field, 'validation_error_field');
}

function setupEditLink(id) {
    var link_container = 'container_showhide_' + id;
    var input_container = 'container_' + id;
    var link = 'showhide_' + id;
    hideEditableField(link_container, input_container, link);
}

/* Hide input/select fields and show the text with (edit) next to it */
function hideEditableField( container, input, action, field_id, original_value, new_value, hide_input ) {
    YAHOO.util.Dom.removeClass(container, 'bz_default_hidden');
    YAHOO.util.Dom.addClass(input, 'bz_default_hidden');
    YAHOO.util.Event.addListener(action, 'click', showEditableField,
                                 new Array(container, input, field_id, new_value));
    if(field_id != ""){
        YAHOO.util.Event.addListener(window, 'load', checkForChangedFieldValues,
                        new Array(container, input, field_id, original_value, hide_input ));
    }
}

/* showEditableField (e, ContainerInputArray)
 * Function hides the (edit) link and the text and displays the input/select field
 *
 * var e: the event
 * var ContainerInputArray: An array containing the (edit) and text area and the input being displayed
 * var ContainerInputArray[0]: the container that will be hidden usually shows the (edit) or (take) text
 * var ContainerInputArray[1]: the input area and label that will be displayed
 * var ContainerInputArray[2]: the input/select field id for which the new value must be set
 * var ContainerInputArray[3]: the new value to set the input/select field to when (take) is clicked
 */
function showEditableField (e, ContainerInputArray) {
    var inputs = new Array();
    var inputArea = YAHOO.util.Dom.get(ContainerInputArray[1]);    
    if ( ! inputArea ){
        YAHOO.util.Event.preventDefault(e);
        return;
    }
    YAHOO.util.Dom.addClass(ContainerInputArray[0], 'bz_default_hidden');
    YAHOO.util.Dom.removeClass(inputArea, 'bz_default_hidden');
    if ( inputArea.tagName.toLowerCase() == "input" ) {
        inputs.push(inputArea);
    } else if (ContainerInputArray[2]) {
        inputs.push(document.getElementById(ContainerInputArray[2]));
    } else {
        inputs = inputArea.getElementsByTagName('input');
    }
    if ( inputs.length > 0 ) {
        // Change the first field's value to ContainerInputArray[2]
        // if present before focusing.
        var type = inputs[0].tagName.toLowerCase();
        if (ContainerInputArray[3]) {
            if ( type == "input" ) {
                inputs[0].value = ContainerInputArray[3];
            } else {
                for (var i = 0; inputs[0].length; i++) {
                    if ( inputs[0].options[i].value == ContainerInputArray[3] ) {
                        inputs[0].options[i].selected = true;
                        break;
                    }
                }
            }
        }
        // focus on the first field, this makes it easier to edit
        inputs[0].focus();
        if ( type == "input" || type == "textarea" ) {
            inputs[0].select();
        }
    }
    YAHOO.util.Event.preventDefault(e);
}


/* checkForChangedFieldValues(e, array )
 * Function checks if after the autocomplete by the browser if the values match the originals.
 *   If they don't match then hide the text and show the input so users don't get confused.
 *
 * var e: the event
 * var ContainerInputArray: An array containing the (edit) and text area and the input being displayed
 * var ContainerInputArray[0]: the conainer that will be hidden usually shows the (edit) text
 * var ContainerInputArray[1]: the input area and label that will be displayed
 * var ContainerInputArray[2]: the field that is on the page, might get changed by browser autocomplete 
 * var ContainerInputArray[3]: the original value from the page loading.
 *
 */  
function checkForChangedFieldValues(e, ContainerInputArray ) {
    var el = document.getElementById(ContainerInputArray[2]);
    var unhide = false;
    if ( el ) {
        if ( !ContainerInputArray[4]
             && (el.value != ContainerInputArray[3]
                 || (el.value == "" && el.id != "qa_contact")) )
        {
            unhide = true;
        }
        else {
            var set_default = document.getElementById("set_default_" +
                                                      ContainerInputArray[2]);
            if ( set_default ) {
                if(set_default.checked){
                    unhide = true;
                }
            }
        }
    }
    if(unhide){
        YAHOO.util.Dom.addClass(ContainerInputArray[0], 'bz_default_hidden');
        YAHOO.util.Dom.removeClass(ContainerInputArray[1], 'bz_default_hidden');
    }

}

function showPeopleOnChange( field_id_list ) {
    for(var i = 0; i < field_id_list.length; i++) {
        YAHOO.util.Event.addListener( field_id_list[i],'change', showEditableField,
                                      new Array('bz_qa_contact_edit_container',
                                                'bz_qa_contact_input'));
        YAHOO.util.Event.addListener( field_id_list[i],'change',showEditableField,
                                      new Array('bz_assignee_edit_container',
                                                'bz_assignee_input'));
    }
}

function assignToDefaultOnChange(field_id_list, default_assignee, default_qa_contact) {
    showPeopleOnChange(field_id_list);
    for(var i = 0, l = field_id_list.length; i < l; i++) {
        YAHOO.util.Event.addListener(field_id_list[i], 'change', function(evt, defaults) {
            if (document.getElementById('assigned_to').value == defaults[0]) {
                setDefaultCheckbox(evt, 'set_default_assignee');
            }
            if (document.getElementById('qa_contact')
                && document.getElementById('qa_contact').value == defaults[1])
            {
                setDefaultCheckbox(evt, 'set_default_qa_contact');
            }
        }, [default_assignee, default_qa_contact]);
    }
}

function initDefaultCheckbox(field_id){
    YAHOO.util.Event.addListener( 'set_default_' + field_id,'change', boldOnChange,
                                  'set_default_' + field_id);
    YAHOO.util.Event.addListener( window,'load', checkForChangedFieldValues,
                                  new Array( 'bz_' + field_id + '_edit_container',
                                             'bz_' + field_id + '_input',
                                             'set_default_' + field_id ,'1'));
    
    YAHOO.util.Event.addListener( window, 'load', boldOnChange,
                                 'set_default_' + field_id ); 
}

function showHideStatusItems(e, dupArrayInfo) {
    var el = document.getElementById('bug_status');
    // finish doing stuff based on the selection.
    if ( el ) {
        showDuplicateItem(el);

        // Make sure that fields whose visibility or values are controlled
        // by "resolution" behave properly when resolution is hidden.
        var resolution = document.getElementById('resolution');
        if (resolution && resolution.options[0].value != '') {
            resolution.bz_lastSelected = resolution.selectedIndex;
            var emptyOption = new Option('', '');
            resolution.insertBefore(emptyOption, resolution.options[0]);
            emptyOption.selected = true;
        }
        YAHOO.util.Dom.addClass('resolution_settings', 'bz_default_hidden');
        if (document.getElementById('resolution_settings_warning')) {
            YAHOO.util.Dom.addClass('resolution_settings_warning',
                                    'bz_default_hidden');
        }
        YAHOO.util.Dom.addClass('duplicate_display', 'bz_default_hidden');


        if ( (el.value == dupArrayInfo[1] && dupArrayInfo[0] == "is_duplicate")
             || bz_isValueInArray(close_status_array, el.value) ) 
        {
            YAHOO.util.Dom.removeClass('resolution_settings', 
                                       'bz_default_hidden');
            YAHOO.util.Dom.removeClass('resolution_settings_warning', 
                                       'bz_default_hidden');

            // Remove the blank option we inserted.
            if (resolution && resolution.options[0].value == '') {
                resolution.removeChild(resolution.options[0]);
                resolution.selectedIndex = resolution.bz_lastSelected;
            }
        }

        if (resolution) {
            bz_fireEvent(resolution, 'change');
        }
    }
}

function showDuplicateItem(e) {
    var resolution = document.getElementById('resolution');
    var bug_status = document.getElementById('bug_status');
    var dup_id = document.getElementById('dup_id');
    if (resolution) {
        if (resolution.value == 'DUPLICATE' && bz_isValueInArray( close_status_array, bug_status.value) ) {
            // hide resolution show duplicate
            YAHOO.util.Dom.removeClass('duplicate_settings', 
                                       'bz_default_hidden');
            YAHOO.util.Dom.addClass('dup_id_discoverable', 'bz_default_hidden');
            // check to make sure the field is visible or IE throws errors
            if( ! YAHOO.util.Dom.hasClass( dup_id, 'bz_default_hidden' ) ){
                dup_id.focus();
                dup_id.select();
            }
        }
        else {
            YAHOO.util.Dom.addClass('duplicate_settings', 'bz_default_hidden');
            YAHOO.util.Dom.removeClass('dup_id_discoverable', 
                                       'bz_default_hidden');
            dup_id.blur();
        }
    }
    YAHOO.util.Event.preventDefault(e); //prevents the hyperlink from going to the url in the href.
}

function setResolutionToDuplicate(e, duplicate_or_move_bug_status) {
    var status = document.getElementById('bug_status');
    var resolution = document.getElementById('resolution');
    YAHOO.util.Dom.addClass('dup_id_discoverable', 'bz_default_hidden');
    status.value = duplicate_or_move_bug_status;
    bz_fireEvent(status, 'change');
    resolution.value = "DUPLICATE";
    bz_fireEvent(resolution, 'change');
    YAHOO.util.Event.preventDefault(e);
}

function setDefaultCheckbox(e, field_id) {
    var el = document.getElementById(field_id);
    var elLabel = document.getElementById(field_id + "_label");
    if( el && elLabel ) {
        el.checked = "true";
        YAHOO.util.Dom.setStyle(elLabel, 'font-weight', 'bold');
    }
}

function boldOnChange(e, field_id){
    var el = document.getElementById(field_id);
    var elLabel = document.getElementById(field_id + "_label");
    if( el && elLabel ) {
        if( el.checked ){
            YAHOO.util.Dom.setStyle(elLabel, 'font-weight', 'bold');
        }
        else{
            YAHOO.util.Dom.setStyle(elLabel, 'font-weight', 'normal');
        }
    }
}

function updateCommentTagControl(checkbox, field) {
    if (checkbox.checked) {
        YAHOO.util.Dom.addClass(field, 'bz_private');
    } else {
        YAHOO.util.Dom.removeClass(field, 'bz_private');
    }
}

/**
 * Reset the value of the classification field and fire an event change
 * on it.  Called when the product changes, in case the classification
 * field (which is hidden) controls the visibility of any other fields.
 */
function setClassification() {
    var classification = document.getElementById('classification');
    var product = document.getElementById('product');
    var selected_product = product.value; 
    var select_classification = all_classifications[selected_product];
    classification.value = select_classification;
    bz_fireEvent(classification, 'change');
}

/**
 * Says that a field should only be displayed when another field has
 * a certain value. May only be called after the controller has already
 * been added to the DOM.
 */
function showFieldWhen(controlled_id, controller_id, values) {
    var controller = document.getElementById(controller_id);
    // Note that we don't get an object for "controlled" here, because it
    // might not yet exist in the DOM. We just pass along its id.
    YAHOO.util.Event.addListener(controller, 'change',
        handleVisControllerValueChange, [controlled_id, controller, values]);
}

/**
 * Called by showFieldWhen when a field's visibility controller 
 * changes values. 
 */
function handleVisControllerValueChange(e, args) {
    var controlled_id = args[0];
    var controller = args[1];
    var values = args[2];

    var field = document.getElementById(controlled_id);
    var label_container =
        document.getElementById('field_label_' + controlled_id);
    var field_container =
        document.getElementById('field_container_' + controlled_id);
    var selected = false;
    for (var i = 0; i < values.length; i++) {
        if (bz_valueSelected(controller, values[i])) {
            selected = true;
            break;
        }
    }

    if (selected) {
        YAHOO.util.Dom.removeClass(label_container, 'bz_hidden_field');
        YAHOO.util.Dom.removeClass(field_container, 'bz_hidden_field');
        /* If a custom field such as a textarea field contains some text, then
         * its content is visible by default as a readonly field (assuming that
         * the field is displayed). But if such a custom field contains no text,
         * then it's not displayed at all and an (edit) link is displayed instead.
         * This is problematic if the custom field is mandatory, because at least
         * Firefox complains that you must enter a value, but is unable to point
         * to the custom field because this one is hidden, and so the user has
         * to guess what the web browser is talking about, which is confusing.
         * So in that case, we display the custom field automatically instead of
         * the (edit) link, so that the user can enter some text in it.
         */
        var field_readonly = document.getElementById(controlled_id + '_readonly');

        if (!field_readonly) {
            var field_input = document.getElementById(controlled_id + '_input');
            var edit_container =
                document.getElementById(controlled_id + '_edit_container');

            if (field_input) {
                YAHOO.util.Dom.removeClass(field_input, 'bz_default_hidden');
            }
            if (edit_container) {
                YAHOO.util.Dom.addClass(edit_container, 'bz_hidden_field');
            }
        }
        // Restore the 'required' attribute for mandatory fields.
        if (field.getAttribute('data-required') == "true") {
            field.setAttribute('required', 'true');
            field.setAttribute('aria-required', 'true');
        }
    }
    else {
        YAHOO.util.Dom.addClass(label_container, 'bz_hidden_field');
        YAHOO.util.Dom.addClass(field_container, 'bz_hidden_field');
        // A hidden field must never be required, because the user cannot set it.
        if (field.getAttribute('data-required') == "true") {
            field.removeAttribute('required');
            field.removeAttribute('aria-required');
        }
    }
}

/**
 * This is a data structure representing the tree of controlled values.
 * Let's call the "controller value" the "source" and the "controlled
 * value" the "target". A target can have only one source, but a source
 * can have an infinite number of targets.
 *
 * The data structure is a series of hash tables that go something
 * like this:
 *
 * source_field -> target_field -> source_value_id -> target_value_ids
 *
 * We always know source_field when our event handler is called, since
 * that's the field the event is being triggered on. We can then enumerate
 * through every target field, check the status of each source field value,
 * and act appropriately on each target value.
 */
var bz_value_controllers = {};
// This keeps track of whether or not we've added an onchange handler
// for the source field yet.
var bz_value_controller_has_handler = {};
function showValueWhen(target_field_id, target_value_ids,
                       source_field_id, source_value_id, empty_shows_all)
{
    if (!bz_value_controllers[source_field_id]) {
        bz_value_controllers[source_field_id] = {};
    }
    if (!bz_value_controllers[source_field_id][target_field_id]) {
        bz_value_controllers[source_field_id][target_field_id] = {};
    }
    var source_values = bz_value_controllers[source_field_id][target_field_id];
    source_values[source_value_id] = target_value_ids;

    if (!bz_value_controller_has_handler[source_field_id]) {
        var source_field = document.getElementById(source_field_id);
        YAHOO.util.Event.addListener(source_field, 'change',
            handleValControllerChange, [source_field, empty_shows_all]);
        bz_value_controller_has_handler[source_field_id] = true;
    }
}

function handleValControllerChange(e, args) {
    var source = args[0];
    var empty_shows_all = args[1];

    for (var target_field_id in bz_value_controllers[source.id]) {
        var target = document.getElementById(target_field_id);
        if (!target) continue;
        _update_displayed_values(source, target, empty_shows_all);
    }
}

/* See the docs for bz_option_duplicate count lower down for an explanation
 * of this data structure.
 */
var bz_option_hide_count = {};

function _update_displayed_values(source, target, empty_shows_all) {
    var show_all = (empty_shows_all && source.selectedIndex == -1);

    bz_option_hide_count[target.id] = {};

    var source_values = bz_value_controllers[source.id][target.id];
    for (source_value_id in source_values) {
        var source_option = getPossiblyHiddenOption(source, source_value_id);
        var target_values = source_values[source_value_id];
        for (var i = 0; i < target_values.length; i++) {
            var target_value_id = target_values[i];
            _handle_source_target(source_option, target, target_value_id,
                                  show_all);
        }
    }

    // We may have updated which elements are selected or not selected
    // in the target field, and it may have handlers associated with
    // that, so we need to fire the change event on the target.
    bz_fireEvent(target, 'change');
}

function _handle_source_target(source_option, target, target_value_id,
                               show_all)
{
    var target_option = getPossiblyHiddenOption(target, target_value_id);

    // We always call either _show_option or _hide_option on every single
    // target value. Although this is not theoretically the most efficient
    // thing we can do, it handles all possible edge cases, and there are
    // a lot of those, particularly when this code is being used on the
    // search form.
    if (source_option.selected || (show_all && !source_option.disabled)) {
        _show_option(target_option, target);
    }
    else {
        _hide_option(target_option, target);
    }
}

/* When an option has duplicates (see the docs for bz_option_duplicates
 * lower down in this file), we only want to hide it if *all* the duplicates
 * would be hidden. So we keep a counter of how many duplicates each option
 * has. Then, when we run through a "change" call for a source field,
 * we count how many times each value gets hidden, and only actually
 * hide it if the counter hits a number higher than the duplicate count.
 */
var bz_option_duplicate_count = {};

function _show_option(option, field) {
    if (!option.disabled) return;
    option = showOptionInIE(option, field);
    YAHOO.util.Dom.removeClass(option, 'bz_hidden_option');
    option.disabled = false;
}

function _hide_option(option, field) {
    if (option.disabled) return;

    var value_id = option.bz_value_id;

    if (field.id in bz_option_duplicate_count
        && value_id in bz_option_duplicate_count[field.id])
    {
        if (!bz_option_hide_count[field.id][value_id]) {
            bz_option_hide_count[field.id][value_id] = 0;
        }
        bz_option_hide_count[field.id][value_id]++;
        var current = bz_option_hide_count[field.id][value_id];
        var dups    = bz_option_duplicate_count[field.id][value_id];
        // We check <= because the value in bz_option_duplicate_count is
        // 1 less than the total number of duplicates (since the shown
        // option is also a "duplicate" but not counted in
        // bz_option_duplicate_count).
        if (current <= dups) return;
    }

    YAHOO.util.Dom.addClass(option, 'bz_hidden_option');
    option.selected = false;
    option.disabled = true;
    hideOptionInIE(option, field);
}

// A convenience function to generate the "id" tag of an <option>
// based on the numeric id that Bugzilla uses for that value.
function _value_id(field_name, id) {
    return 'v' + id + '_' + field_name;
}

/*********************************/
/* Code for Hiding Options in IE */
/*********************************/

/* IE 7 and below (and some other browsers) don't respond to "display: none"
 * on <option> tags. However, you *can* insert a Comment Node as a
 * child of a <select> tag. So we just insert a Comment where the <option>
 * used to be. */
var ie_hidden_options = {};
function hideOptionInIE(anOption, aSelect) {
    if (browserCanHideOptions(aSelect)) return;

    var commentNode = document.createComment(anOption.value);
    commentNode.id = anOption.id;
    // This keeps the interface of Comments and Options the same for
    // our other functions.
    commentNode.disabled = true;
    // replaceChild is very slow on IE in a <select> that has a lot of
    // options, so we use replaceNode when we can.
    if (anOption.replaceNode) {
        anOption.replaceNode(commentNode);
    }
    else {
        aSelect.replaceChild(commentNode, anOption);
    }

    // Store the comment node for quick access for getPossiblyHiddenOption
    if (!ie_hidden_options[aSelect.id]) {
        ie_hidden_options[aSelect.id] = {};
    }
    ie_hidden_options[aSelect.id][anOption.id] = commentNode;
}

function showOptionInIE(aNode, aSelect) {
    if (browserCanHideOptions(aSelect)) return aNode;

    // We do this crazy thing with innerHTML and createElement because
    // this is the ONLY WAY that this works properly in IE.
    var optionNode = document.createElement('option');
    optionNode.innerHTML = aNode.data;
    optionNode.value = aNode.data;
    optionNode.id = aNode.id;
    // replaceChild is very slow on IE in a <select> that has a lot of
    // options, so we use replaceNode when we can.
    if (aNode.replaceNode) {
        aNode.replaceNode(optionNode);
    }
    else {
        aSelect.replaceChild(optionNode, aNode);
    }
    delete ie_hidden_options[aSelect.id][optionNode.id];
    return optionNode;
}

function initHidingOptionsForIE(select_name) {
    var aSelect = document.getElementById(select_name);
    if (browserCanHideOptions(aSelect)) return;
    if (!aSelect) return;

    for (var i = 0; ;i++) {
        var item = aSelect.options[i];
        if (!item) break;
        if (item.disabled) {
          hideOptionInIE(item, aSelect);
          i--; // Hiding an option means that the options array has changed.
        }
    }
}

/* Certain fields, like the Component field, have duplicate values in
 * them (the same name, but different ids). We don't display these
 * duplicate values in the UI, but the option hiding/showing code still
 * uses the ids of these unshown duplicates. So, whenever we get the
 * id of an unshown duplicate in getPossiblyHiddenOption, we have to
 * return the actually-used <option> instead.
 *
 * The structure of the data looks like:
 *
 *  field_name -> unshown_value_id -> shown_value_id_it_is_a_duplicate_of
 */
var bz_option_duplicates = {};

function getPossiblyHiddenOption(aSelect, optionId) {

    if (bz_option_duplicates[aSelect.id]
        && bz_option_duplicates[aSelect.id][optionId])
    {
        optionId = bz_option_duplicates[aSelect.id][optionId];
    }

    // Works always for <option> tags, and works for commentNodes
    // in IE (but not in Webkit).
    var id = _value_id(aSelect.id, optionId);
    var val = document.getElementById(id);

    // This is for WebKit and other browsers that can't "display: none"
    // an <option> and also can't getElementById for a commentNode.
    if (!val && ie_hidden_options[aSelect.id]) {
        val = ie_hidden_options[aSelect.id][id];
    }

    // We add this property for our own convenience, it's used in
    // other places.
    val.bz_value_id = optionId;

    return val;
}

var browser_can_hide_options;
function browserCanHideOptions(aSelect) {
    /* As far as I can tell, browsers that don't hide <option> tags
     * also never have a X position for <option> tags, even if
     * they're visible. This is the only reliable way I found to
     * differentiate browsers. So we create a visible option, see
     * if it has a position, and then remove it. */
    if (typeof(browser_can_hide_options) == "undefined") {
        var new_opt = bz_createOptionInSelect(aSelect, '', '');
        var opt_pos = YAHOO.util.Dom.getX(new_opt);
        aSelect.removeChild(new_opt);
        if (opt_pos) {
            browser_can_hide_options = true;
        }
        else {
            browser_can_hide_options = false;
        }
    }
    return browser_can_hide_options;
}

/* (end) option hiding code */

/**
 * Autocompletion
 */

$(function() {

    // single user

    function searchComplete() {
        var that = $(this);
        that.data('counter', that.data('counter') - 1);
        if (that.data('counter') === 0)
            that.removeClass('autocomplete-running');
        if (document.activeElement != this)
            that.autocomplete('hide');
    };

    var options_user = {
        serviceUrl: 'rest/user',
        params: {
            Bugzilla_api_token: BUGZILLA.api_token,
            include_fields: 'name,real_name',
            limit: 100
        },
        paramName: 'match',
        deferRequestBy: 250,
        minChars: 3,
        tabDisabled: true,
        transformResult: function(response) {
            response = $.parseJSON(response);
            return {
                suggestions: $.map(response.users, function(dataItem) {
                    return {
                        value: dataItem.name,
                        data : { login: dataItem.name, name: dataItem.real_name }
                    };
                })
            };
        },
        formatResult: function(suggestion, currentValue) {
            return (suggestion.data.name === '' ?
                suggestion.data.login : suggestion.data.name + ' (' + suggestion.data.login + ')')
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;');
        },
        onSearchStart: function(params) {
            var that = $(this);
            params.match = $.trim(params.match);
            that.addClass('autocomplete-running');
            that.data('counter', that.data('counter') + 1);
        },
        onSearchComplete: searchComplete,
        onSearchError: searchComplete
    };

    // multiple users (based on single user)
    var options_users = {
        delimiter: /,\s*/,
        onSelect: function() {
            this.focus();
        },
    };
    $.extend(options_users, options_user);

    // init user autocomplete fields
    $('.bz_autocomplete_user')
        .each(function() {
            var that = $(this);
            that.data('counter', 0);
            if (that.data('multiple')) {
                that.devbridgeAutocomplete(options_users);
            }
            else {
                that.devbridgeAutocomplete(options_user);
            }
            that.addClass('bz_autocomplete');
        });

    // init autocomplete fields with array of values
    $('.bz_autocomplete_values')
        .each(function() {
            var that = $(this);
            that.devbridgeAutocomplete({
                lookup: BUGZILLA.autocomplete_values[that.data('values')],
                tabDisabled: true,
                delimiter: /,\s*/,
                minChars: 0,
                onSelect: function() {
                    this.focus();
                }
            });
            that.addClass('bz_autocomplete');
        });
});

/**
 * Set the disable email checkbox to true if the user has disabled text
 */
function userDisabledTextOnChange(disabledtext) {
    var disable_mail = document.getElementById('disable_mail');
    if (disabledtext.value === "" && !disable_mail_manually_set) {
        disable_mail.checked = false;
    }
    if (disabledtext.value !== "" && !disable_mail_manually_set) {
        disable_mail.checked = true;
    }
}

/**
 * Force the browser to honour the selected option when a page is refreshed,
 * but only if the user hasn't explicitly selected a different option.
 */
function initDirtyFieldTracking() {
    // old IE versions don't provide the information we need to make this fix work
    // however they aren't affected by this issue, so it's ok to ignore them
    if (YAHOO.env.ua.ie > 0 && YAHOO.env.ua.ie <= 8) return;
    var selects = document.getElementById('changeform').getElementsByTagName('select');
    for (var i = 0, l = selects.length; i < l; i++) {
        var el = selects[i];
        var el_dirty = document.getElementById(el.name + '_dirty');
        if (!el_dirty) continue;
        if (!el_dirty.value) {
            var preSelected = bz_preselectedOptions(el);
            if (!el.multiple) {
                preSelected.selected = true;
            } else {
                el.selectedIndex = -1;
                for (var j = 0, m = preSelected.length; j < m; j++) {
                    preSelected[j].selected = true;
                }
            }
        }
        YAHOO.util.Event.on(el, "change", function(e) {
            var el = e.target || e.srcElement;
            var preSelected = bz_preselectedOptions(el);
            var currentSelected = bz_selectedOptions(el);
            var isDirty = false;
            if (!el.multiple) {
                isDirty = preSelected.index != currentSelected.index;
            } else {
                if (preSelected.length != currentSelected.length) {
                    isDirty = true;
                } else {
                    for (var i = 0, l = preSelected.length; i < l; i++) {
                        if (currentSelected[i].index != preSelected[i].index) {
                            isDirty = true;
                            break;
                        }
                    }
                }
            }
            document.getElementById(el.name + '_dirty').value = isDirty ? '1' : '';
        });
    }
}

/**
 * Comment preview
 */

var last_comment_text = '';
var last_markdown_cb_value = null;
var comment_textarea_width = null;
var comment_textarea_height = null;

function refresh_markdown_preview (bug_id) {
    if (!YAHOO.util.Dom.hasClass('comment_preview_tab', 'active_comment_tab'))
        return;
    show_comment_preview(bug_id, 1);
}

function show_comment_preview(bug_id, refresh) {
    var Dom = YAHOO.util.Dom;
    var comment = document.getElementById('comment');
    var preview = document.getElementById('comment_preview');
    var markdown_cb = document.getElementById('use_markdown');

    if (!comment || !preview) return;
    if (Dom.hasClass('comment_preview_tab', 'active_comment_tab') && !refresh)
        return;

    if (!comment_textarea_width) {
        comment_textarea_width = (comment.clientWidth - 4) + 'px';
        comment_textarea_height = comment.offsetHeight + 'px';
    }

    preview.style.width = comment_textarea_width;
    preview.style.height = comment_textarea_height;

    var comment_tab = document.getElementById('comment_tab');
    Dom.addClass(comment, 'bz_default_hidden');
    Dom.removeClass(comment_tab, 'active_comment_tab');
    comment_tab.setAttribute('aria-selected', 'false');

    var preview_tab = document.getElementById('comment_preview_tab');
    Dom.removeClass(preview, 'bz_default_hidden');
    Dom.addClass(preview_tab, 'active_comment_tab');
    preview_tab.setAttribute('aria-selected', 'true');

    Dom.addClass('comment_preview_error', 'bz_default_hidden');

    if (last_comment_text == comment.value && last_markdown_cb_value == markdown_cb.checked)
        return;

    Dom.addClass('comment_preview_text', 'bz_default_hidden');
    Dom.removeClass('comment_preview_loading', 'bz_default_hidden');

    YAHOO.util.Connect.setDefaultPostHeader('application/json', true);
    YAHOO.util.Connect.asyncRequest('POST', 'jsonrpc.cgi',
    {
        success: function(res) {
            data = YAHOO.lang.JSON.parse(res.responseText);
            if (data.error) {
                Dom.addClass('comment_preview_loading', 'bz_default_hidden');
                Dom.removeClass('comment_preview_error', 'bz_default_hidden');
                Dom.get('comment_preview_error').innerHTML =
                    YAHOO.lang.escapeHTML(data.error.message);
            } else {
                document.getElementById('comment_preview_text').innerHTML = data.result.html;
                Dom.addClass('comment_preview_loading', 'bz_default_hidden');
                Dom.removeClass('comment_preview_text', 'bz_default_hidden');
                if (markdown_cb.checked) {
                    Dom.removeClass('comment_preview_text', 'comment_preview_pre');
                }
                else {
                    Dom.addClass('comment_preview_text', 'comment_preview_pre');
                }
                last_comment_text = comment.value;
                last_markdown_cb_value = markdown_cb.checked;
            }
            if (markdown_cb.checked) {
                var pres = document.getElementById('comment_preview_text').getElementsByTagName("pre");
                for (var i = 0, l = pres.length; i < l; i++) {
                    if (pres[i].firstChild && pres[i].firstChild.tagName == "CODE") {
                        hljs.highlightBlock(pres[i].firstChild);
                    }
                }
            }
        },
        failure: function(res) {
            Dom.addClass('comment_preview_loading', 'bz_default_hidden');
            Dom.removeClass('comment_preview_error', 'bz_default_hidden');
            Dom.get('comment_preview_error').innerHTML =
                YAHOO.lang.escapeHTML(res.responseText);
        }
    },
    YAHOO.lang.JSON.stringify({
        version: "1.1",
        method: 'Bug.render_comment',
        params: {
            Bugzilla_api_token: BUGZILLA.api_token,
            id: bug_id,
            text: comment.value,
            markdown: (markdown_cb != null) && markdown_cb.checked ? 1 : 0
        }
    })
    );
}

function show_comment_edit() {
    var comment = document.getElementById('comment');
    var preview = document.getElementById('comment_preview');
    if (!comment || !preview) return;
    if (YAHOO.util.Dom.hasClass(comment, 'active_comment_tab')) return;

    var preview_tab = document.getElementById('comment_preview_tab');
    YAHOO.util.Dom.addClass(preview, 'bz_default_hidden');
    YAHOO.util.Dom.removeClass(preview_tab, 'active_comment_tab');
    preview_tab.setAttribute('aria-selected', 'false');

    var comment_tab = document.getElementById('comment_tab');
    YAHOO.util.Dom.removeClass(comment, 'bz_default_hidden');
    YAHOO.util.Dom.addClass(comment_tab, 'active_comment_tab');
    comment_tab.setAttribute('aria-selected', 'true');
}

function adjustRemainingTime() {
    // subtracts time spent from remaining time
    // prevent negative values if work_time > bz_remaining_time
    var new_time = Math.max(bz_remaining_time - document.changeform.work_time.value, 0.0);
    // get upto 2 decimal places
    document.changeform.remaining_time.value = Math.round(new_time * 100)/100;
}

function updateRemainingTime() {
    // if the remaining time is changed manually, update bz_remaining_time
    bz_remaining_time = document.changeform.remaining_time.value;
}
