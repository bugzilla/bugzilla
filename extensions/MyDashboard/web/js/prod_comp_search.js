/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

// Product and component search to file a new bug
YUI({
    base: 'js/yui3/',
    combine: false
}).use("node", "json-stringify", "autocomplete", "escape",
       "datasource-io", "datasource-jsonschema", "array-extras", function (Y) {
    var counter = 0,
        format = '',
        cloned_bug_id = '',
        dataSource = null,
        autoComplete = null;

    var resultListFormat = function(query, results) {
        return Y.Array.map(results, function (result) {
            var data = result.raw;
            return Y.Escape.html(data.product) + " :: " +
                   Y.Escape.html(data.component);
        });
    };

    var requestTemplate = function(query) {
        counter = counter + 1;
        var json_object = {
            version: "1.1",
            method : "MyDashboard.prod_comp_search",
            id : counter,
            params : { search: query }
        };
        return Y.JSON.stringify(json_object);
    };

    var dataSource = new Y.DataSource.IO({
        source: 'jsonrpc.cgi',
        ioConfig: {
            method: "POST",
            headers: { 'Content-Type': 'application/json' }
        }
    });

    dataSource.plug(Y.Plugin.DataSourceJSONSchema, {
        schema: {
            resultListLocator : "result.products",
            resultFields : [ "product", "component" ]
        }
    });

    var input = Y.one('#prod_comp_search');

    input.plug(Y.Plugin.AutoComplete, {
        enableCache: true,
        source: dataSource,
        minQueryLength: 3,
        queryDelay: 0.05,
        resultFormatter: resultListFormat,
        maxResultsDisplayed: 25,
        suppressInputUpdate: true,
        maxResults: 25,
        requestTemplate: requestTemplate,
        on: {
            query: function() {
                Y.one("#prod_comp_throbber").removeClass('bz_default_hidden');
            },
            results: function() {
                Y.one("#prod_comp_throbber").addClass('bz_default_hidden');
            },
            select: function(e) {
                var data = e.result.raw;
                var url = "enter_bug.cgi?product=" + encodeURIComponent(data.product) +
                          "&component=" +  encodeURIComponent(data.component);
                window.location.href = url;
            }
        },
    });

    input.on('focus', function (e) {
        if (e.target.value && e.target.value.length > 3) {
            dataSource.load(e.target.value);
        }
    });
});
