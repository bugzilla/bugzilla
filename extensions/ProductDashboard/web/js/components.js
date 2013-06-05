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
}).use("datatable", "datatable-sort", "escape", function(Y) {
    if (typeof PD.updated_recently != 'undefined') {
        var columns = [
            { key:"id", label:"ID", sortable:true, allowHTML: true,
              formatter: '<a href="show_bug.cgi?id={value}" target="_blank">{value}</a>' },
            { key:"bug_status", label:"Status", sortable:true },
            { key:"version", label:"Version", sortable:true },
            { key:"component", label:"Component", sortable:true },
            { key:"severity", label:"Severity", sortable:true },
            { key:"summary", label:"Summary", sortable:false },
        ];

        var updatedRecentlyDataTable = new Y.DataTable({
            columns: columns,
            data: PD.updated_recently
        });
        updatedRecentlyDataTable.render("#updated_recently");

        if (typeof PD.past_due != 'undefined') {
            var pastDueDataTable = new Y.DataTable({
                columns: columns,
                data: PD.past_due
            });
            pastDueDataTable.render('#past_due');
        }
    }

    if (typeof PD.component_counts != 'undefined') {
        var summary_url = '<a href="page.cgi?id=productdashboard.html&amp;product=' +
                          encodeURIComponent(PD.product_name) + '&bug_status=' +
                          encodeURIComponent(PD.bug_status) + '&tab=components';

        var columns = [
            { key:"name", label:"Name", sortable:true, allowHTML: true,
              formatter: function (o) {
                  return summary_url + '&component=' +
                         encodeURIComponent(o.value) + '">' +
                         Y.Escape.html(o.value) + '</a>'
              }
            },
            { key:"count", label:"Count", sortable:true },
            { key:"percentage", label:"Percentage", sortable:false, allowHTML: true,
              formatter: '<div class="percentage"><div class="bar" style="width:{value}%"></div><div class="percent">{value}%</div></div>' },
            { key:"link", label:"Link", sortable:false, allowHTML: true }
        ];

        var componentsDataTable = new Y.DataTable({
            columns: columns,
            data: PD.component_counts
        });
        componentsDataTable.render("#component_counts");

        columns[0].formatter = function (o) {
            return summary_url + '&version=' +
                   encodeURIComponent(o.value) + '">' +
                   Y.Escape.html(o.value) + '</a>';
        };

        var versionsDataTable = new Y.DataTable({
            columns: columns,
            data: PD.version_counts
        });
        versionsDataTable.render('#version_counts');

        if (typeof PD.milestone_counts != 'undefined') {
            columns[0].formatter = function (o) {
                return summary_url + '&target_milestone=' +
                       encodeURIComponent(o.value) + '">' +
                       Y.Escape.html(o.value) + '</a>';
            };

            var milestonesDataTable = new Y.DataTable({
                columns: columns,
                data: PD.milestone_counts
            });
            milestonesDataTable.render('#milestone_counts');
        }
    }
});
