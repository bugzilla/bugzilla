/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

// Flag tables
YUI({
    base: 'js/yui3/',
    combine: false
}).use("node", "datatable", "datatable-sort", "json-stringify", "escape",
       "datatable-datasource", "datasource-io", "datasource-jsonschema", function (Y) {
    // Common
    var counter = 0;
    var dataSource = {
        requestee: null,
        requester: null
    };
    var dataTable = {
        requestee: null,
        requester: null
    };

    var updateFlagTable = function (type) {
        if (!type) return;

        counter = counter + 1;

        var callback = {
            success: function(e) {
                if (e.response) {
                    Y.one('#' + type + '_count_refresh').removeClass('bz_default_hidden');
                    Y.one("#" + type + "_flags_found").setHTML(
                        e.response.results.length + ' flags found');
                    dataTable[type].set('data', e.response.results);
                }
            },
            failure: function(o) {
                var resp = o.responseText;
                alert("IO request failed : " + resp);
            }
        };

        var json_object = {
            version: "1.1",
            method:  "MyDashboard.run_flag_query",
            id:      counter,
            params:  { type : type }
        };

        var stringified = Y.JSON.stringify(json_object);

        Y.one('#' + type + '_count_refresh').addClass('bz_default_hidden');
                
        dataTable[type].set('data', []);
        dataTable[type].render("#" + type + "_table");
        dataTable[type].showMessage('loadingMessage');

        dataSource[type].sendRequest({
            request: stringified,
            cfg: {
                method:  "POST",
                headers: { 'Content-Type': 'application/json' }
            },
            callback: callback
        });
    };

    var bugLinkFormatter = function (o) {
        return '<a href="show_bug.cgi?id=' + encodeURIComponent(o.value) +
               '" target="_blank" ' + 'title="' + Y.Escape.html(o.data.bug_status) + ' - ' + 
               Y.Escape.html(o.data.bug_summary) + '">' + o.value + '</a>';
    };

    var createdFormatter = function (o) {
        return '<span title="' + Y.Escape.html(o.value) + '">' +
               Y.Escape.html(o.data.created_fancy) + '</span>';
    };

    var requesteeFormatter = function (o) {
        return o.value
            ? Y.Escape.html(o.value)
            : '<i>anyone</i>';
    };

    // Requestee
    dataSource.requestee = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
    dataTable.requestee = new Y.DataTable({
        columns: [
            { key: "requester", label: "Requester", sortable: true },
            { key: "type", label: "Flag", sortable: true },
            { key: "bug_id", label: "Bug", sortable: true, 
              formatter: bugLinkFormatter, allowHTML: true },
            { key: "created", label: "Created", sortable: true, 
              formatter: createdFormatter, allowHTML: true }
        ],
        strings: {
            emptyMessage: 'No flag data found.',
        }
    });

    dataTable.requestee.plug(Y.Plugin.DataTableSort);

    dataTable.requestee.plug(Y.Plugin.DataTableDataSource, {
        datasource: dataSource,
        initialRequest: updateFlagTable("requestee"),
    });

    dataSource.requestee.plug(Y.Plugin.DataSourceJSONSchema, {
        schema: {
            resultListLocator: "result.result.requestee",
            resultFields: ["requester", "type", "bug_id", "bug_status",
                           "bug_summary", "created", "created_fancy"]
        }
    });

    dataTable.requestee.render("#requestee_table");

    Y.one('#requestee_refresh').on('click', function(e) {
        updateFlagTable('requestee');
    });

    // Requester
    dataSource.requester = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
    dataTable.requester = new Y.DataTable({
        columns: [
            { key:"requestee", label:"Requestee", sortable:true,
              formatter: requesteeFormatter, allowHTML: true },
            { key:"type", label:"Flag", sortable:true },
            { key:"bug_id", label:"Bug", sortable:true,
              formatter: bugLinkFormatter, allowHTML: true },
            { key: "created", label: "Created", sortable: true,
              formatter: createdFormatter, allowHTML: true }
        ],
        strings: {
            emptyMessage: 'No flag data found.',
        }
    });

    dataTable.requester.plug(Y.Plugin.DataTableSort);

    dataTable.requester.plug(Y.Plugin.DataTableDataSource, {
        datasource: dataSource,
        initialRequest: updateFlagTable("requester"),
    });

    dataSource.requester.plug(Y.Plugin.DataSourceJSONSchema, {
        schema: {
            resultListLocator: "result.result.requester",
            resultFields: ["requestee", "type", "bug_id", "bug_status",
                           "bug_summary", "created", "created_fancy"]
        }
    });

    Y.one('#requester_refresh').on('click', function(e) {
        updateFlagTable('requester');
    });
});
