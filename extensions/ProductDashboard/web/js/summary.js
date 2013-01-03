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
        { key: 'name', label: 'Name', sortable: true },
        { key: 'count', label: 'Count', sortable: true },
        { key: 'percentage', label: 'Percentage', sortable: true, allowHTML: true, 
          formatter: '<div class="percentage"><div class="bar" style="width:{value}%"></div><div class="percent">{value}%</div></div>' }, 
        { key: 'link', label: 'Link', allowHTML: true }
    ];

    var bugsCountDataTable = new Y.DataTable({
        columns: column_defs,
        data: PD.summary.bug_counts
    }).render('#bug_counts');

    var statusCountsDataTable = new Y.DataTable({
        columns: column_defs,
        data: PD.summary.status_counts
    }).render('#status_counts');

    var priorityCountsDataTable = new Y.DataTable({
        columns: column_defs,
        data: PD.summary.priority_counts
    }).render('#priority_counts');

    var severityCountsDataTable = new Y.DataTable({
        columns: column_defs,
        data: PD.summary.severity_counts
    }).render('#severity_counts');

    var assigneeCountsDataTable = new Y.DataTable({
        columns: column_defs,
        data: PD.summary.assignee_counts
    }).render('#assignee_counts');
});
