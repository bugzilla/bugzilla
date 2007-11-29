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
    var timeRe = /(\d\d):(\d\d)(?::(\d\d))?/;
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
        var hours = d.getHours();
        if (hours < 10) hours = '0' + String(hours);
        d.setHours(hours);
        var minutes = d.getMinutes();
        if (minutes < 10) minutes = '0' + String(minutes);
        var seconds = d.getSeconds();
        if (seconds > 0 && seconds < 10) {
            seconds = '0' + String(seconds);
        }

        dateStr = dateStr + ' ' + hours + ':' + minutes;
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
