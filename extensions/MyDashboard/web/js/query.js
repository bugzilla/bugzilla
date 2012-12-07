/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

// Main query code
YUI({
    base: 'js/yui3/',
    combine: false
}).use("node", "datatable", "datatable-sort", "json-stringify",
       "datatable-datasource", "datasource-io", "datasource-jsonschema",
       "gallery-paginator-view", "gallery-datatable-paginator", function (Y) {
    var counter = 0,
        dataSource = null,
        dataTable = null;

    var updateQueryTable = function(query_name) {
        if (!query_name) return;

        counter = counter + 1;

        var callback = {
            success: function(e) {
                if (e.response) {
                    Y.one("#query_container .query_description").setHTML(e.response.meta.description);
                    Y.one("#query_container .query_heading").setHTML(e.response.meta.heading);
                    Y.one("#query_bugs_found").setHTML(
                        '<a href="buglist.cgi?' + e.response.meta.buffer +
                        '">' + e.response.results.length + ' bugs found</a>');
                    Y.one("#query_container .status").addClass('bz_default_hidden');
                    dataTable.set('data', e.response.results);
                    dataTable.render("#query_table");
                }
            },
            failure: function(o) {
                var resp = o.responseText;
                alert("IO request failed : " + resp);
            }
        };

        var json_object = {
            version: "1.1",
            method:  "MyDashboard.run_bug_query",
            id:      counter,
            params:  { query : query_name }
        };

        var stringified = Y.JSON.stringify(json_object);

        Y.one("#query_container .status").removeClass('bz_default_hidden');

        dataSource.sendRequest({
            request: stringified,
            cfg: {
                method:  "POST",
                headers: { 'Content-Type': 'application/json' }
            },
            callback: callback
        });
    };

    dataSource = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
    dataTable = new Y.DataTable({
        columns: [
            { key:"bug_id", label:"Bug", sortable:true,
              formatter: '<a href="show_bug.cgi?id={value}" target="_blank">{value}</a>', allowHTML: true },
            { key:"changeddate", label:"Updated", sortable:true },
            { key:"bug_status", label:"Status", sortable:true },
            { key:"short_desc", label:"Summary", sortable:true },
        ],
        strings: {
            emptyMessage: 'No query data found.',
        },
        paginator: new Y.PaginatorView({
            model: new Y.PaginatorModel({ itemsPerPage: 25 }),
            container: 'query_pagination_top',
        })
    });

    dataTable.plug(Y.Plugin.DataTableSort);

    dataTable.plug(Y.Plugin.DataTableDataSource, {
        datasource: dataSource,
        initialRequest: updateQueryTable("assignedbugs"),
    });

    dataSource.plug(Y.Plugin.DataSourceJSONSchema, {
        schema: {
            resultListLocator: "result.result.bugs",
            resultFields: ["bug_id", "changeddate", "bug_status", "short_desc"],
            metaFields: {
                description: "result.result.description",
                heading:     "result.result.heading",
                buffer:      "result.result.buffer"
            }
        }
    });

    Y.one('#query').on('change', function(e) {
        var index = e.target.get('selectedIndex');
        var selected_value = e.target.get("options").item(index).getAttribute('value');
        updateQueryTable(selected_value);
    });

    Y.one('#query_refresh').on('click', function(e) {
        var query_select = Y.one('#query');
        var index = query_select.get('selectedIndex');
        var selected_value = query_select.get("options").item(index).getAttribute('value');
        updateQueryTable(selected_value);
    });
});
