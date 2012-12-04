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
        Y.log(results);
        return Y.Array.map(results, function (result) {
            var data = result.raw;
            return Y.Escape.html(data.product) + " :: " +
                   Y.Escape.html(data.component);
        });
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
            resultsListLocator : "result.products",
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
        requestTemplate: function (query) {
            counter = counter + 1;
            var json_object = {
                version: "1.1",
                method : "MyDashboard.prod_comp_search",
                id : counter,
                params : { search: query }
            };
            return Y.JSON.stringify(json_object);
        },
//        resultListLocator: 'response.result.products',
//        resultListLocator: 'result.products'
//        resultListLocator: function (response) {
//            Y.log(response);
//            return (response && response.data && response.data.result.products) || [];
//        },
//            // Makes sure an array is returned even on an error.
//            if (response.error) {
//                return [];
//            }
//
//            Y.log(response);
//
//            return response.query.results;
//
//            return [{
//                product: "Foo",
//                component: "Bar"
//            }];
//            var query = response.query.results.json,
//                addresses;
//
//            if (query.status !== 'OK') {
//                return [];
//            }
//
//            // Grab the actual addresses from the YQL query.
//            addresses = query.results;
//
//            // Makes sure an array is always returned.
//            return addresses.length > 0 ? addresses : [addresses];
//        },
    });

    input.ac.on('query', function() {
        Y.one("#prod_comp_throbber").removeClass('bz_default_hidden');
    });

    input.ac.after('results', function() {
        Y.one("#prod_comp_throbber").addClass('bz_default_hidden');
    });

    input.ac.on('select', function (itemNode, result) {
        var url  = "enter_bug.cgi?product=" + encodeURIComponent(result.component) +
                   "&component=" +  encodeURIComponent(result.product);
        Y.log(url);
        //autoComplete.dataReturnEvent.subscribe(function(type, args) {
        //    args[0].autoHighlight = args[2].length == 1;
        //});
//        doBeforeLoadData: function(sQuery, oResponse, oPayload) {
//            Y.one("#prod_comp_throbber").addClass('bz_default_hidden');
//            return true;
//        }
    });

//    autoComplete.textboxFocusEvent.subscribe(function () {
//        var input = Y.one(field);
//        if (input.value && input.value.length > 3) {
//            sendQuery(input.value);
//        }
//    });
});
