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
        { key: 'percentage', label: 'Percentage', sortable: false, allowHTML: true,
          formatter: '<div class="percentage"><div class="bar" style="width:{value}%"></div><div class="percent">{value}%</div></div>' },
        { key: 'link', label: 'Links', allowHTML: true, sortable: false }
    ];

    var roadmapDataTable = new Y.DataTable({
        columns: column_defs,
        data: PD.roadmap,
    }).render('#bug_milestones');
});
