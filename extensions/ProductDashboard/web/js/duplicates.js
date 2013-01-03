/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

YUI({
    base: 'js/yui3/',
    combine: false
}).use("datatable", "datatable-sort", function (Y) {
    var column_defs = [
        { key:"id", label:"ID", sortable:true, allowHTML: true,
          formatter: '<a href="show_bug.cgi?id={value}" target="_blank">{value}</a>' },
        { key:"count", label:"Count", sortable:true },
        { key:"status", label:"Status", sortable:true },
        { key:"version", label:"Version", sortable:true },
        { key:"component", label:"Component", sortable:true },
        { key:"severity", label:"Severity", sortable:true },
        { key:"summary", label:"Summary", sortable:false },
    ];

    var duplicatesDataTable = new Y.DataTable({
        columns: column_defs,
        data: PD.duplicates
    }).render('#duplicates');
});
