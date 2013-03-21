/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

// Product and component search to file a new bug

var ProdCompSearch = {
    script_name: 'enter_bug.cgi',
    script_choices: ['enter_bug.cgi', 'describecomponents.cgi'],
    format: null,
    cloned_bug_id: null,
    new_tab: null
};

YUI({
    base: 'js/yui3/',
    combine: false
}).use("node", "json-stringify", "autocomplete", "escape",
       "datasource-io", "datasource-jsonschema", function (Y) {
    var counter = 0,
        dataSource = null,
        autoComplete = null;

    var resultListFormat = function(query, results) {
        return Y.Array.map(results, function(result) {
            var data = result.raw;
            result.text = data.product + ' :: ' + data.component;
            return Y.Escape.html(result.text);
        });
    };

    var requestTemplate = function(query) {
        counter = counter + 1;
        var json_object = {
            version: "1.1",
            method : "PCS.prod_comp_search",
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
        activateFirstItem: false,
        enableCache: true,
        source: dataSource,
        minQueryLength: 3,
        queryDelay: 0.05,
        resultFormatter: resultListFormat,
        suppressInputUpdate: true,
        maxResults: 25,
        scrollIntoView: true,
        requestTemplate: requestTemplate,
        on: {
            query: function(e) {
                Y.one("#prod_comp_throbber").removeClass('bz_default_hidden');
                Y.one("#prod_comp_no_components").addClass('bz_default_hidden');
            },
            results: function(e) {
                Y.one("#prod_comp_throbber").addClass('bz_default_hidden');
                input.ac.set('activateFirstItem', e.results.length == 1);
                if (e.results.length == 0) {
                    Y.one("#prod_comp_no_components").removeClass('bz_default_hidden');
                }
            },
            select: function(e) {
                // Only redirect if the script_name is a valid choice
                if (Y.Array.indexOf(ProdCompSearch.script_choices, ProdCompSearch.script_name) == -1)
                    return;

                var data = e.result.raw;
                var url = ProdCompSearch.script_name + 
                          "?product=" + encodeURIComponent(data.product) +
                          "&component=" +  encodeURIComponent(data.component);
                if (ProdCompSearch.script_name == 'enter_bug.cgi') {
                    if (ProdCompSearch.format)
                        url += "&format=" + encodeURIComponent(ProdCompSearch.format);
                    if (ProdCompSearch.cloned_bug_id)
                        url += "&cloned_bug_id=" + encodeURIComponent(ProdCompSearch.cloned_bug_id);
                }
                if (ProdCompSearch.script_name == 'describecomponents.cgi') {
                    url += "#" + encodeURIComponent(data.component);
                }
                if (ProdCompSearch.new_tab) {
                    window.open(url, '_blank');
                }
                else {
                    window.location.href = url;
                }
            }
        },
        after: {
            select: function(e) {
                if (ProdCompSearch.new_tab) {
                    input.set('value','');
                }
            }
        }
    });

    input.on('focus', function (e) {
        if (e.target.value && e.target.value.length > 3) {
            dataSource.load(e.target.value);
        }
    });
});
