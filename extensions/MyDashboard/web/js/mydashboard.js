/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

var showQuerySection = function () {
    var query_select = YAHOO.util.Dom.get('query');
    var selected_value = '';
    for (var i = 0, l = query_select.options.length; i < l; i++) {
        if (query_select.options[i].selected) {
            selected_value = query_select.options[i].value;
        }
    }
    for (var i = 0, l = full_query_list.length; i < l; i++) {
        var query = full_query_list[i];
        if (selected_value == full_query_list[i]) {
            YAHOO.util.Dom.removeClass(query + '_container', 'bz_default_hidden');
        }
        else {
            YAHOO.util.Dom.addClass(query + '_container', 'bz_default_hidden');
        }
    }
}

var query_column_defs = [
    { key:"id", label:"ID", sortable:true, sortOptions:{ sortFunction:sortBugIdLinks } },
    { key:"updated", label:"Updated", sortable:true },
    { key:"bug_status", label:"Status", sortable:true },
    { key:"summary", label:"Summary", sortable:true },
];

var query_fields = [
    { key:"id" },
    { key:"updated" },
    { key:"bug_status" },
    { key:"summary" }
];

var requestee_column_defs = [
  { key:"requester", label:"Requester", sortable:true },
  { key:"flag", label:"Flag", sortable:true },
  { key:"bug", label:"Bug", sortable:true },
  { key:"created", label:"Created", sortable:true }
];

var requestee_fields = [
  { key:"requester" },
  { key:"flag" },
  { key:"bug" },
  { key:"created" }
];

var requester_column_defs = [
  { key:"requestee", label:"Requestee", sortable:true },
  { key:"flag", label:"Flag", sortable:true },
  { key:"bug", label:"Bug", sortable:true },
  { key:"created", label:"Created", sortable:true }
];

var requester_fields = [
  { key:"requestee" },
  { key:"flag" },
  { key:"bug" },
  { key:"created" }
];

function addStatListener (div_name, table_name, column_defs, fields, options) {
    YAHOO.util.Event.addListener(window, "load", function() {
        YAHOO.example.StatsFromMarkup = new function() {
            this.myDataSource = new YAHOO.util.DataSource(YAHOO.util.Dom.get(table_name));
            this.myDataSource.responseType = YAHOO.util.DataSource.TYPE_HTMLTABLE;
            this.myDataSource.responseSchema = { fields:fields };
            this.myDataTable = new YAHOO.widget.DataTable(div_name, column_defs, this.myDataSource, options);
            this.myDataTable.subscribe("rowMouseoverEvent", this.myDataTable.onEventHighlightRow); 
            this.myDataTable.subscribe("rowMouseoutEvent", this.myDataTable.onEventUnhighlightRow); 
        };
    });
}

// Custom sort handler to sort by bug id inside an anchor tag
var sortBugIdLinks = function(a, b, desc) {
    // Deal with empty values
    if (!YAHOO.lang.isValue(a)) {
        return (!YAHOO.lang.isValue(b)) ? 0 : 1;
    }
    else if(!YAHOO.lang.isValue(b)) {
        return -1;
    }
    // Now we need to pull out the ID text and convert to Numbers
    // First we do 'a'
    var container = document.createElement("bug_id_link");
    container.innerHTML = a.getData("id");
    var anchors = container.getElementsByTagName("a");
    var text = anchors[0].textContent;
    if (text === undefined) text = anchors[0].innerText;
    var new_a = new Number(text);
    // Then we do 'b'
    container.innerHTML = b.getData("id");
    anchors = container.getElementsByTagName("a");
    text = anchors[0].textContent;
    if (text == undefined) text = anchors[0].innerText;
    var new_b = new Number(text);

    if (!desc) {
        return YAHOO.util.Sort.compare(new_a, new_b);
    }
    else {
        return YAHOO.util.Sort.compare(new_b, new_a);
    }
}

// Custom sort handler for bug severities
var sortBugSeverity = function(a, b, desc) {
    // Deal with empty values
    if (!YAHOO.lang.isValue(a)) {
        return (!YAHOO.lang.isValue(b)) ? 0 : 1; 
    }
    else if(!YAHOO.lang.isValue(b)) {
        return -1;
    }

    var new_a = new Number(severities[YAHOO.lang.trim(a.getData('bug_severity'))]);
    var new_b = new Number(severities[YAHOO.lang.trim(b.getData('bug_severity'))]);

    if (!desc) {
        return YAHOO.util.Sort.compare(new_a, new_b);
    }
    else {
        return YAHOO.util.Sort.compare(new_b, new_a);
    }
}

// Custom sort handler for bug priorities
var sortBugPriority = function(a, b, desc) {
    // Deal with empty values
    if (!YAHOO.lang.isValue(a)) {
        return (!YAHOO.lang.isValue(b)) ? 0 : 1;
    }
    else if(!YAHOO.lang.isValue(b)) {
        return -1;
    }

    var new_a = new Number(priorities[YAHOO.lang.trim(a.getData('priority'))]);
    var new_b = new Number(priorities[YAHOO.lang.trim(b.getData('priority'))]);

    if (!desc) {
        return YAHOO.util.Sort.compare(new_a, new_b);
    }
    else {
        return YAHOO.util.Sort.compare(new_b, new_a);
    }
}
