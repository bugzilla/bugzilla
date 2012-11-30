/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

// Main query code
YUI().use("node", "datatable", "datatable-sort", "json-stringify",
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
            container: '#query_pagination_top'
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

// Flag tables
YUI().use("node", "datatable", "datatable-sort", "json-stringify",
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
                    Y.one("#" + type + "_flags_found").setHTML(
                        e.response.results.length + ' flags found');
                    Y.one("#" + type + "_container .status").addClass('bz_default_hidden');
                    dataTable[type].set('data', e.response.results);
                    dataTable[type].render("#" + type + "_table");
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

        Y.one("#" + type + "_container .status").removeClass('bz_default_hidden');

        dataSource[type].sendRequest({
            request: stringified,
            cfg: {
                method:  "POST",
                headers: { 'Content-Type': 'application/json' }
            },
            callback: callback
        });
    };

    // Requestee
    dataSource.requestee = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
    dataTable.requestee = new Y.DataTable({
        columns: [
            { key:"requester", label:"Requester", sortable:true },
            { key:"flag", label:"Flag", sortable:true },
            { key:"bug_id", label:"Bug", sortable:true,
              formatter: '<a href="show_bug.cgi?id={value}" target="_blank">{value}</a>', allowHTML: true },
            { key:"changeddate", label:"Updated", sortable:true },
            { key:"created", label:"Created", sortable:true }
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
            resultFields: ["requester", "flag", "bug_id", "created"]
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
            { key:"requestee", label:"Requestee", sortable:true },
            { key:"flag", label:"Flag", sortable:true },
            { key:"bug_id", label:"Bug", sortable:true,
              formatter: '<a href="show_bug.cgi?id={value}" target="_blank">{value}</a>', allowHTML: true },
            { key:"created", label:"Created", sortable:true }
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
            resultFields: ["requestee", "flag", "bug_id", "created"]
        }
    });

    Y.one('#requester_refresh').on('click', function(e) {
        updateFlagTable('requester');
    });
});

YUI().use("node", "json-stringify", "autocomplete", "autocomplete-highlighters",
          "datasource-io", "datasource-jsonschema", function (Y) {
    var counter = 0,
        format = '',
        cloned_bug_id = '',
        dataSource = null,
        autoComplete = null;

    var generateRequest = function (enteredText) {
        counter = counter + 1;
        var json_object = {
            version: "1.1",
            method : "MyDashboard.prod_comp_search",
            id : counter,
            params : { search: enteredText }
        };
        Y.one("#prod_comp_throbber").removeClass('bz_default_hidden');
        return Y.JSON.stringify(json_object);
    };

    var resultListFormat = function(oResultData, enteredText, sResultMatch) {
        return Y.Lang.escapeHTML(oResultData[0]) + " :: " +
               Y.Lang.escapeHTML(oResultData[1]);
    };

    var dataSource = new Y.DataSource.IO({
        source: 'jsonrpc.cgi',
        connTimeout: 30000,
        connMethodPost: true,
        connXhrMode: 'cancelStaleRequests',
        maxCacheEntries: 5,
        responseSchema: {
            resultsList : "result.products",
            metaFields : { error: "error", jsonRpcId: "id"},
            fields : [ "product", "component" ]
        }
    });

    Y.one('#prod_comp_search').plug(Y.Plugin.AutoComplete, {
        resultHighlighter: 'phraseMatch',
        source: dataSource,
        minQueryLength: 3,
        queryDelay: 0.05,
        generateRequest: generateRequest,
        formatResult: resultListFormat,
        maxResultsDisplayed: 25,
        suppressInputUpdate: true,
        doBeforeLoadData: function(sQuery, oResponse, oPayload) {
            Y.one("#prod_comp_throbber").addClass('bz_default_hidden');
            return true;
        }
    });

//    autoComplete.textboxFocusEvent.subscribe(function () {
//        var input = Y.one(field);
//        if (input.value && input.value.length > 3) {
//            sendQuery(input.value);
//        }
//    });
//
//    autoComplete.itemSelectEvent.subscribe(function (e, args) {
//        var oData = args[2];
//        var url  = "enter_bug.cgi?product=" + encodeURIComponent(oData[0]) +
//                   "&component=" +  encodeURIComponent(oData[1]);
//        autoComplete.dataReturnEvent.subscribe(function(type, args) {
//            args[0].autoHighlight = args[2].length == 1;
//        });
//    });
});
