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
       "datatable-datasource", "datasource-io", "datasource-jsonschema", function(Y) {
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

    var updateFlagTable = function(type) {
        if (!type) return;

        var include_closed = Y.one('#' + type + '_closed').get('checked') ? 1 : 0;

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
            params:  { type : type, include_closed: include_closed }
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

    var loadBugList = function(type) {
        if (!type) return;
        var data = dataTable[type].data;
        var ids = [];
        for (var i = 0, l = data.size(); i < l; i++) {
            ids.push(data.item(i).get('bug_id'));
        }
        var url = 'buglist.cgi?bug_id=' + ids.join('%2C');
        window.open(url, '_blank');
    };

    var bugLinkFormatter = function(o) {
        var bug_closed = "";
        if (o.data.bug_status == 'RESOLVED' || o.data.bug_status == 'VERIFIED') {
            bug_closed = "bz_closed";
        }
        return '<a href="show_bug.cgi?id=' + encodeURIComponent(o.value) +
               '" target="_blank" ' + 'title="' + Y.Escape.html(o.data.bug_status) + ' - ' +
               Y.Escape.html(o.data.bug_summary) + '" class="' + Y.Escape.html(bug_closed) +
               '">' + o.value + '</a>';
    };

    var updatedFormatter = function(o) {
        return '<span title="' + Y.Escape.html(o.value) + '">' +
               Y.Escape.html(o.data.updated_fancy) + '</span>';
    };

    var requesteeFormatter = function(o) {
        return o.value
            ? Y.Escape.html(o.value)
            : '<i>anyone</i>';
    };

    var flagNameFormatter = function(o) {
        if (parseInt(o.data.attach_id)
            && parseInt(o.data.is_patch)
            && MyDashboard.splinter_base)
        {
            return '<a href="' + MyDashboard.splinter_base +
                   (MyDashboard.splinter_base.indexOf('?') == -1 ? '?' : '&') +
                   'bug=' + encodeURIComponent(o.data.bug_id) +
                   '&attachment=' + encodeURIComponent(o.data.attach_id) +
                   '" target="_blank" title="Review this patch">' +
                   Y.Escape.html(o.value) + '</a>';
        }
        else {
            return Y.Escape.html(o.value);
        }
    };

    // Requestee
    dataSource.requestee = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
    dataTable.requestee = new Y.DataTable({
        columns: [
            { key: "requester", label: "Requester", sortable: true },
            { key: "type", label: "Flag", sortable: true,
              formatter: flagNameFormatter, allowHTML: true },
            { key: "bug_id", label: "Bug", sortable: true,
              formatter: bugLinkFormatter, allowHTML: true },
            { key: "updated", label: "Updated", sortable: true,
              formatter: updatedFormatter, allowHTML: true }
        ],
        strings: {
            emptyMessage: 'No flag data found.',
        }
    });

    dataTable.requestee.plug(Y.Plugin.DataTableSort);

    dataTable.requestee.plug(Y.Plugin.DataTableDataSource, {
        datasource: dataSource.requestee
    });

    dataSource.requestee.plug(Y.Plugin.DataSourceJSONSchema, {
        schema: {
            resultListLocator: "result.result.requestee",
            resultFields: ["requester", "type", "attach_id", "is_patch", "bug_id",
                           "bug_status", "bug_summary", "updated", "updated_fancy"]
        }
    });

    dataTable.requestee.render("#requestee_table");

    Y.one('#requestee_refresh').on('click', function(e) {
        updateFlagTable('requestee');
    });
    Y.one('#requestee_buglist').on('click', function(e) {
        loadBugList('requestee');
    });
    Y.one('#requestee_closed').on('change', function(e) {
        updateFlagTable('requestee');
    });

    // Requester
    dataSource.requester = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
    dataTable.requester = new Y.DataTable({
        columns: [
            { key:"requestee", label:"Requestee", sortable:true,
              formatter: requesteeFormatter, allowHTML: true },
            { key:"type", label:"Flag", sortable:true,
              formatter: flagNameFormatter, allowHTML: true },
            { key:"bug_id", label:"Bug", sortable:true,
              formatter: bugLinkFormatter, allowHTML: true },
            { key: "updated", label: "Updated", sortable: true,
              formatter: updatedFormatter, allowHTML: true }
        ],
        strings: {
            emptyMessage: 'No flag data found.',
        }
    });

    dataTable.requester.plug(Y.Plugin.DataTableSort);

    dataTable.requester.plug(Y.Plugin.DataTableDataSource, {
        datasource: dataSource.requester
    });

    dataSource.requester.plug(Y.Plugin.DataSourceJSONSchema, {
        schema: {
            resultListLocator: "result.result.requester",
            resultFields: ["requestee", "type", "attach_id", "is_patch", "bug_id",
                           "bug_status", "bug_summary", "updated", "updated_fancy"]
        }
    });

    // Initial load
    Y.on("contentready", function (e) {
        updateFlagTable("requestee");
    }, "#requestee_table");
    Y.on("contentready", function (e) {
        updateFlagTable("requester");
    }, "#requester_table");

    Y.one('#requester_refresh').on('click', function(e) {
        updateFlagTable('requester');
    });
    Y.one('#requester_buglist').on('click', function(e) {
        loadBugList('requester');
    });
    Y.one('#requester_closed').on('change', function(e) {
        updateFlagTable('requester');
    });
});
