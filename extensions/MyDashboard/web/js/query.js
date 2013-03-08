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
    combine: false, 
    groups: {
        gallery: {
            combine: false,
            base: 'js/yui3/',
            patterns: { 'gallery-': {} }
        }
    }
}).use("node", "datatable", "datatable-sort", "datatable-message", "json-stringify",
       "datatable-datasource", "datasource-io", "datasource-jsonschema", "cookie",
       "gallery-datatable-row-expansion-bmo", "handlebars", "escape", function (Y) {
    var counter = 0,
        dataSource = null,
        dataTable = null, 
        default_query = "assignedbugs";

    // Grab last used query name from cookie or use default
    var query_cookie = Y.Cookie.get("my_dashboard_query");
    if (query_cookie) {
        var cookie_value_found = 0;
        Y.one("#query").get("options").each( function() {
            if (this.get("value") == query_cookie) {
                this.set('selected', true);
                default_query = query_cookie;
                cookie_value_found = 1;
            }
        });
        if (!cookie_value_found) {
            Y.Cookie.set("my_dashboard_query", "");
        }
    }

    var updateQueryTable = function(query_name) {
        if (!query_name) return;

        counter = counter + 1;

        var callback = {
            success: function(e) {
                if (e.response) {
                    Y.one('#query_count_refresh').removeClass('bz_default_hidden');
                    Y.one("#query_container .query_description").setHTML(e.response.meta.description);
                    Y.one("#query_container .query_heading").setHTML(e.response.meta.heading);
                    Y.one("#query_bugs_found").setHTML(
                        '<a href="buglist.cgi?' + e.response.meta.buffer +
                        '">' + e.response.results.length + ' bugs found</a>');
                    dataTable.set('data', e.response.results);
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

        Y.one('#query_count_refresh').addClass('bz_default_hidden');

        dataTable.set('data', []);
        dataTable.render("#query_table");
        dataTable.showMessage('loadingMessage');

        dataSource.sendRequest({
            request: stringified,
            cfg: {
                method:  "POST",
                headers: { 'Content-Type': 'application/json' }
            },
            callback: callback
        });
    };

    var updatedFormatter = function (o) {
        return '<span title="' + Y.Escape.html(o.value) + '">' +
               Y.Escape.html(o.data.changeddate_fancy) + '</span>';
    };

    dataSource = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });

    dataSource.plug(Y.Plugin.DataSourceJSONSchema, {
        schema: {
            resultListLocator: "result.result.bugs",
            resultFields: ["bug_id", "changeddate", "changeddate_fancy",
                           "bug_status", "short_desc", "last_changes"],
            metaFields: {
                description: "result.result.description",
                heading:     "result.result.heading",
                buffer:      "result.result.buffer"
            }
        }
    });

    dataTable = new Y.DataTable({
        columns: [
            { key: Y.Plugin.DataTableRowExpansion.column_key, label: ' ', sortable: false },
            { key: "bug_id", label: "Bug", allowHTML: true,
              formatter: '<a href="show_bug.cgi?id={value}" target="_blank">{value}</a>' },
            { key: "changeddate", label: "Updated", formatter: updatedFormatter, allowHTML: true },
            { key: "bug_status", label: "Status" },
            { key: "short_desc", label: "Summary" },
        ],
        sortable: true
    });

    var last_changes_source = Y.one('#last-changes-template').getHTML(),
        last_changes_template = Y.Handlebars.compile(last_changes_source);

    dataTable.plug(Y.Plugin.DataTableRowExpansion, {
        uniqueIdKey: 'bug_id',
        template: function(data) {
            var last_changes = {};
            if (data.last_changes.email) {
                last_changes = {
                    activity: data.last_changes.activity, 
                    email: data.last_changes.email,
                    when: data.last_changes.when, 
                    comment: data.last_changes.comment,
                };
            }
            return last_changes_template(last_changes);
        }
    });

    dataTable.plug(Y.Plugin.DataTableSort);

    dataTable.plug(Y.Plugin.DataTableDataSource, {
        datasource: dataSource,
        initialRequest: updateQueryTable(default_query),
    });

    Y.one('#query').on('change', function(e) {
        var index = e.target.get('selectedIndex');
        var selected_value = e.target.get("options").item(index).getAttribute('value');
        updateQueryTable(selected_value);
        Y.Cookie.set("my_dashboard_query", selected_value, { expires: new Date("January 12, 2025") });
    });

    Y.one('#query_refresh').on('click', function(e) {
        var query_select = Y.one('#query');
        var index = query_select.get('selectedIndex');
        var selected_value = query_select.get("options").item(index).getAttribute('value');
        updateQueryTable(selected_value);
    });
});
