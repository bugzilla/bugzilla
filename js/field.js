/* The contents of this file are subject to the Mozilla Public
 * License Version 1.1 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy of
 * the License at http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS
 * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * The Original Code is the Bugzilla Bug Tracking System.
 *
 * The Initial Developer of the Original Code is Everything Solved, Inc.
 * Portions created by Everything Solved are Copyright (C) 2007 Everything
 * Solved, Inc. All Rights Reserved.
 *
 * Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>
 *                 Guy Pyrzak <guy.pyrzak@gmail.com>
 */

/* This library assumes that the needed YUI libraries have been loaded 
   already. */

function createCalendar(name) {
    var cal = new YAHOO.widget.Calendar('calendar_' + name, 
                                        'con_calendar_' + name);
    YAHOO.bugzilla['calendar_' + name] = cal;
    var field = document.getElementById(name);
    cal.selectEvent.subscribe(setFieldFromCalendar, field, false);
    updateCalendarFromField(field);
    cal.render();
}

/* The onclick handlers for the button that shows the calendar. */
function showCalendar(field_name) {
    var calendar  = YAHOO.bugzilla["calendar_" + field_name];
    var field     = document.getElementById(field_name);
    var button    = document.getElementById('button_calendar_' + field_name);

    bz_overlayBelow(calendar.oDomContainer, field);
    calendar.show();
    button.onclick = function() { hideCalendar(field_name); };

    // Because of the way removeListener works, this has to be a function
    // attached directly to this calendar.
    calendar.bz_myBodyCloser = function(event) {
        var container = this.oDomContainer;
        var target    = YAHOO.util.Event.getTarget(event);
        if (target != container && target != button
            && !YAHOO.util.Dom.isAncestor(container, target))
        {
            hideCalendar(field_name);
        }
    };

    // If somebody clicks outside the calendar, hide it.
    YAHOO.util.Event.addListener(document.body, 'click', 
                                 calendar.bz_myBodyCloser, calendar, true);

    // Make Esc close the calendar.
    calendar.bz_escCal = function (event) {
        var key = YAHOO.util.Event.getCharCode(event);
        if (key == 27) {
            hideCalendar(field_name);
        }
    };
    YAHOO.util.Event.addListener(document.body, 'keydown', calendar.bz_escCal);
}

function hideCalendar(field_name) {
    var cal = YAHOO.bugzilla["calendar_" + field_name];
    cal.hide();
    var button = document.getElementById('button_calendar_' + field_name);
    button.onclick = function() { showCalendar(field_name); };
    YAHOO.util.Event.removeListener(document.body, 'click',
                                    cal.bz_myBodyCloser);
    YAHOO.util.Event.removeListener(document.body, 'keydown', cal.bz_escCal);
}

/* This is the selectEvent for our Calendar objects on our custom 
 * DateTime fields.
 */
function setFieldFromCalendar(type, args, date_field) {
    var dates = args[0];
    var setDate = dates[0];

    // We can't just write the date straight into the field, because there 
    // might already be a time there.
    var timeRe = /\b(\d{1,2}):(\d\d)(?::(\d\d))?/;
    var currentTime = timeRe.exec(date_field.value);
    var d = new Date(setDate[0], setDate[1] - 1, setDate[2]);
    if (currentTime) {
        d.setHours(currentTime[1], currentTime[2]);
        if (currentTime[3]) {
            d.setSeconds(currentTime[3]);
        }
    }

    var year = d.getFullYear();
    // JavaScript's "Date" represents January as 0 and December as 11.
    var month = d.getMonth() + 1;
    if (month < 10) month = '0' + String(month);
    var day = d.getDate();
    if (day < 10) day = '0' + String(day);
    var dateStr = year + '-' + month  + '-' + day;

    if (currentTime) {
        var minutes = d.getMinutes();
        if (minutes < 10) minutes = '0' + String(minutes);
        var seconds = d.getSeconds();
        if (seconds > 0 && seconds < 10) {
            seconds = '0' + String(seconds);
        }

        dateStr = dateStr + ' ' + d.getHours() + ':' + minutes;
        if (seconds) dateStr = dateStr + ':' + seconds;
    }

    date_field.value = dateStr;
    hideCalendar(date_field.id);
}

/* Sets the calendar based on the current field value. 
 */ 
function updateCalendarFromField(date_field) {
    var dateRe = /(\d\d\d\d)-(\d\d?)-(\d\d?)/;
    var pieces = dateRe.exec(date_field.value);
    if (pieces) {
        var cal = YAHOO.bugzilla["calendar_" + date_field.id];
        cal.select(new Date(pieces[1], pieces[2] - 1, pieces[3]));
        var selectedArray = cal.getSelectedDates();
        var selected = selectedArray[0];
        cal.cfg.setProperty("pagedate", (selected.getMonth() + 1) + '/' 
                                        + selected.getFullYear());
        cal.render();
    }
}


/* Hide input fields and show the text with (edit) next to it */  
function hideEditableField( container, input, action, field_id, original_value ) {
    YAHOO.util.Dom.setStyle(container, 'display', 'inline');
    YAHOO.util.Dom.setStyle(input, 'display', 'none');
    YAHOO.util.Event.addListener(action, 'click', showEditableField,
                                 new Array(container, input));
    if(field_id != ""){
        YAHOO.util.Event.addListener(window, 'load', checkForChangedFieldValues,
                        new Array(container, input, field_id, original_value));
    }
}

/* showEditableField (e, ContainerInputArray)
 * Function hides the (edit) link and the text and displays the input
 *
 * var e: the event
 * var ContainerInputArray: An array containing the (edit) and text area and the input being displayed
 * var ContainerInputArray[0]: the conainer that will be hidden usually shows the (edit) text
 * var ContainerInputArray[1]: the input area and label that will be displayed
 *
 */
function showEditableField (e, ContainerInputArray) {
    YAHOO.util.Dom.setStyle(ContainerInputArray[0], 'display', 'none');
    YAHOO.util.Dom.setStyle(ContainerInputArray[1], 'display', 'inline');
    var inputs = YAHOO.util.Dom.get(ContainerInputArray[1]).getElementsByTagName('input')
    if( inputs.length > 0) {
        // focus on the first field, this makes it easier to edit
        inputs[0].focus();
        inputs[0].select();
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
        if ( el.value != ContainerInputArray[3] ||
            ( el.value == "" && el.id != "alias") ) {
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
        YAHOO.util.Dom.setStyle(ContainerInputArray[0], 'display', 'none');
        YAHOO.util.Dom.setStyle(ContainerInputArray[1], 'display', 'inline');
    }

}

function hideAliasAndSummary(short_desc_value, alias_value) {
    // check the short desc field
    hideEditableField( 'summary_alias_container','summary_alias_input',
                       'editme_action','short_desc', short_desc_value);  
    // check that the alias hasn't changed
    var bz_alias_check_array = new Array('summary_alias_container',
                                     'summary_alias_input', 'alias', alias_value);
    YAHOO.util.Event.addListener( window, 'load', checkForChangedFieldValues,
                                 bz_alias_check_array);
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

function assignToDefaultOnChange(field_id_list) {
    showPeopleOnChange( field_id_list );
    for(var i = 0; i < field_id_list.length; i++) {
        YAHOO.util.Event.addListener( field_id_list[i],'change', setDefaultCheckbox,
                                      'set_default_assignee');
        YAHOO.util.Event.addListener( field_id_list[i],'change',setDefaultCheckbox,
                                      'set_default_qa_contact');    
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
        YAHOO.util.Dom.setStyle('resolution_settings', 'display', 'none');
        if (document.getElementById('resolution_settings_warning')) {
            YAHOO.util.Dom.setStyle('resolution_settings_warning', 'display', 'none');
        }
        YAHOO.util.Dom.setStyle('duplicate_display', 'display', 'none');

        if ( el.value == dupArrayInfo[1] && dupArrayInfo[0] == "is_duplicate" ) {
            YAHOO.util.Dom.setStyle('resolution_settings', 'display', 'inline');
            YAHOO.util.Dom.setStyle('resolution_settings_warning', 'display', 'block');  
        }
        else if ( bz_isValueInArray(close_status_array, el.value) ) {
            // hide duplicate and show resolution
            YAHOO.util.Dom.setStyle('resolution_settings', 'display', 'inline');
            YAHOO.util.Dom.setStyle('resolution_settings_warning', 'display', 'block');
        }
    }
}

function showDuplicateItem(e) {
    var resolution = document.getElementById('resolution');
    var bug_status = document.getElementById('bug_status');
    if (resolution) {
        if (resolution.value == 'DUPLICATE' && bz_isValueInArray( close_status_array, bug_status.value) ) {
            // hide resolution show duplicate
            YAHOO.util.Dom.setStyle('duplicate_settings', 'display', 'inline');
            YAHOO.util.Dom.setStyle('dup_id_discoverable', 'display', 'none');
        }
        else {
            YAHOO.util.Dom.setStyle('duplicate_settings', 'display', 'none');
            YAHOO.util.Dom.setStyle('dup_id_discoverable', 'display', 'block');
        }
    }
    YAHOO.util.Event.preventDefault(e); //prevents the hyperlink from going to the url in the href.
}

function setResolutionToDuplicate(e, duplicate_or_move_bug_status) {
    var status = document.getElementById('bug_status');
    var resolution = document.getElementById('resolution');
    YAHOO.util.Dom.setStyle('dup_id_discoverable', 'display', 'none');
    status.value = duplicate_or_move_bug_status;
    resolution.value = "DUPLICATE";
    showHideStatusItems("", ["",""]);
    YAHOO.util.Event.preventDefault(e);
}

function setDefaultCheckbox(e, field_id ) { 
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

function updateCommentTagControl(checkbox, form) {
    if (checkbox.checked) {
        form.comment.className='bz_private';
    } else {
        form.comment.className='';
    }
}

/**
 * Says that a field should only be displayed when another field has
 * a certain value. May only be called after the controller has already
 * been added to the DOM.
 */
function showFieldWhen(controlled_id, controller_id, value) {
    var controller = document.getElementById(controller_id);
    // Note that we don't get an object for "controlled" here, because it
    // might not yet exist in the DOM. We just pass along its id.
    YAHOO.util.Event.addListener(controller, 'change', 
        handleVisControllerValueChange, [controlled_id, controller, value]);
}

/**
 * Called by showFieldWhen when a field's visibility controller 
 * changes values. 
 */
function handleVisControllerValueChange(e, args) {
    var controlled_id = args[0];
    var controller = args[1];
    var value = args[2];

    var label_container = 
        document.getElementById('field_label_' + controlled_id);
    var field_container =
        document.getElementById('field_container_' + controlled_id);
    if (bz_valueSelected(controller, value)) {
        YAHOO.util.Dom.removeClass(label_container, 'bz_hidden_field');
        YAHOO.util.Dom.removeClass(field_container, 'bz_hidden_field');
    }
    else {
        YAHOO.util.Dom.addClass(label_container, 'bz_hidden_field');
        YAHOO.util.Dom.addClass(field_container, 'bz_hidden_field');
    }
}

function showValueWhen(controlled_field_id, controlled_value, 
                       controller_field_id, controller_value)
{
    var controller_field = document.getElementById(controller_field_id);
    // Note that we don't get an object for the controlled field here, 
    // because it might not yet exist in the DOM. We just pass along its id.
    YAHOO.util.Event.addListener(controller_field, 'change',
        handleValControllerChange, [controlled_field_id, controlled_value,
                                    controller_field, controller_value]);
}

function handleValControllerChange(e, args) {
    var controlled_field = document.getElementById(args[0]);
    var controlled_value = args[1];
    var controller_field = args[2];
    var controller_value = args[3];

    var item = getPossiblyHiddenOption(controlled_field, controlled_value);
    if (bz_valueSelected(controller_field, controller_value)) {
        showOptionInIE(item, controlled_field);
        YAHOO.util.Dom.removeClass(item, 'bz_hidden_option');
        item.disabled = false;
    }
    else if (!item.disabled) {
        YAHOO.util.Dom.addClass(item, 'bz_hidden_option');
        if (item.selected) {
            item.selected = false;
            bz_fireEvent(controlled_field, 'change');
        }
        item.disabled = true;
        hideOptionInIE(item, controlled_field);
    }
}

/*********************************/
/* Code for Hiding Options in IE */
/*********************************/

/* IE 7 and below (and some other browsers) don't respond to "display: none"
 * on <option> tags. However, you *can* insert a Comment Node as a
 * child of a <select> tag. So we just insert a Comment where the <option>
 * used to be. */
function hideOptionInIE(anOption, aSelect) {
    if (browserCanHideOptions(aSelect)) return;

    var commentNode = document.createComment(anOption.value);
    aSelect.replaceChild(commentNode, anOption);
}

function showOptionInIE(aNode, aSelect) {
    if (browserCanHideOptions(aSelect)) return;
    // If aNode is an Option
    if (typeof(aNode.value) != 'undefined') return;

    // We do this crazy thing with innerHTML and createElement because
    // this is the ONLY WAY that this works properly in IE.
    var optionNode = document.createElement('option');
    optionNode.innerHTML = aNode.data;
    optionNode.value = aNode.data;
    var old_node = aSelect.replaceChild(optionNode, aNode);
}

function initHidingOptionsForIE(select_name) {
    var aSelect = document.getElementById(select_name);
    if (browserCanHideOptions(aSelect)) return;

    for (var i = 0; ;i++) {
        var item = aSelect.options[i];
        if (!item) break;
        if (item.disabled) {
          hideOptionInIE(item, aSelect);
          i--; // Hiding an option means that the options array has changed.
        }
    }
}

function getPossiblyHiddenOption(aSelect, aValue) {
    var val_index = bz_optionIndex(aSelect, aValue);

    /* We have to go fishing for one of our comment nodes if we
     * don't find the <option>. */
    if (val_index < 0 && !browserCanHideOptions(aSelect)) {
        var children = aSelect.childNodes;
        for (var i = 0; i < children.length; i++) {
            var item = children[i];
            if (item.data == aValue) {
                // Set this for handleValControllerChange, so that both options
                // and commentNodes have this.
                children[i].disabled = true;
                return children[i];
            }
        }
    }

    /* Otherwise we just return the Option we found. */
    return aSelect.options[val_index];
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
