/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

// Flag tables
$(function () {
    YUI({
        base: 'js/yui3/',
        combine: false
    }).use("node", "datatable", "datatable-sort", "json-stringify", "escape",
        "datatable-datasource", "datasource-io", "datasource-jsonschema", function(Y) {
        // Common
        var counter = 0;
        var dataSource = {
            reviews: null,
            requestee: null,
            requester: null
        };
        var dataTable = {
            reviews: null,
            requestee: null,
            requester: null
        };
        var hasReviews = !!document.getElementById('reviews_container');

        var updateRequestsTable = function(type) {
            if (!type) return;

            counter = counter + 1;

            var callback = {
                success: function(e) {
                    if (e.response) {
                        Y.one('#' + type + '_loading').addClass('bz_default_hidden');
                        Y.one('#' + type + '_count_refresh').removeClass('bz_default_hidden');
                        Y.one("#" + type + "_flags_found").setHTML(
                            e.response.results.length +
                            ' request' + (e.response.results.length == 1 ? '' : 's') +
                            ' found');
                        dataTable[type].set('data', e.response.results);
                    }
                },
                failure: function(o) {
                    Y.one('#' + type + '_loading').addClass('bz_default_hidden');
                    Y.one('#' + type + '_count_refresh').removeClass('bz_default_hidden');
                    if (o.error && o.error.message) {
                        alert("Failed to load requests:\n\n" + o.error.message);
                    } else {
                        alert("Failed to load requests.");
                    }
                }
            };

            var method = type === 'reviews' ? 'PhabBugz.needs_review' : 'MyDashboard.run_flag_query';
            var json_object = {
                version: "1.1",
                method:  method,
                id:      counter,
                params:  {
                    type : type,
                    Bugzilla_api_token : (BUGZILLA.api_token ? BUGZILLA.api_token : '')
                }
            };

            var stringified = Y.JSON.stringify(json_object);

            Y.one('#' + type + '_loading').removeClass('bz_default_hidden');
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
            if (!o.data.bug_id) {
                return '-';
            }
            var bug_closed = "";
            if (o.data.bug_status == 'RESOLVED' || o.data.bug_status == 'VERIFIED') {
                bug_closed = "bz_closed";
            }
            return '<a href="show_bug.cgi?id=' + encodeURIComponent(o.data.bug_id) +
                '" target="_blank" ' + 'title="' + Y.Escape.html(o.data.bug_status) + ' - ' +
                Y.Escape.html(o.data.bug_summary) + '" class="' + bug_closed +
                '">' + o.data.bug_id + '</a>';
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

        var phabAuthorFormatter = function(o) {
            return '<span title="' + Y.Escape.html(o.data.author_email) + '">' +
                Y.Escape.html(o.data.author_name) + '</span>';
        };

        var phabRowFormatter = function(o) {
            var row = o.cell.ancestor();

            // space in the 'flags' tables is tight
            // render requests as two rows - diff title on first row, columns
            // on second

            row.insert(
                '<tr class="' + row.getAttribute('class') + '">' +
                '<td class="yui3-datatable-cell" colspan="4">' +
                '<a href="' + o.data.url + '" target="_blank">' +
                Y.Escape.html('D' + o.data.id + ' - ' + o.data.title) +
                '</a></td></tr>',
                'before');

            o.cell.set('text', o.data.status == 'added' ? 'pending' : o.data.status);

            return false;
        };

        // Reviews
        if (hasReviews) {
            dataSource.reviews = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
            dataSource.reviews.on('error', function(e) {
                console.log(e);
                try {
                    var response = Y.JSON.parse(e.data.responseText);
                    if (response.error)
                        e.error.message = response.error.message;
                } catch(ex) {
                    // ignore
                }
            });
            dataTable.reviews = new Y.DataTable({
                columns: [
                    { key: 'author_email', label: 'Requester', sortable: true,
                        formattter: phabAuthorFormatter, allowHTML: true },
                    { key: 'bug_id', label: 'Bug', sortable: true,
                        formatter: bugLinkFormatter, allowHTML: true },
                    { key: 'updated', label: 'Updated', sortable: true,
                        formatter: updatedFormatter, allowHTML: true }
                ],
                strings: {
                    emptyMessage: 'No review requests.',
                }
            });

            dataTable.reviews.plug(Y.Plugin.DataTableSort);

            dataTable.reviews.plug(Y.Plugin.DataTableDataSource, {
                datasource: dataSource.reviews
            });

            dataSource.reviews.plug(Y.Plugin.DataSourceJSONSchema, {
                schema: {
                    resultListLocator: 'result.result',
                    resultFields: [ 'author_email', 'author_name', 'bug_id',
                        'bug_status', 'bug_summary', 'id', 'status', 'title',
                        'updated', 'updated_fancy', 'url' ]
                }
            });

            dataTable.reviews.render("#reviews_table");

            Y.one('#reviews_refresh').on('click', function(e) {
                updateRequestsTable('reviews');
            });
            Y.one('#reviews_buglist').on('click', function(e) {
                loadBugList('reviews');
            });
        }

        // Requestee
        dataSource.requestee = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
        dataSource.requestee.on('error', function(e) {
            try {
                var response = Y.JSON.parse(e.data.responseText);
                if (response.error)
                    e.error.message = response.error.message;
            } catch(ex) {
                // ignore
            }
        });
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
                emptyMessage: 'No flags requested of you.',
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
            updateRequestsTable('requestee');
        });
        Y.one('#requestee_buglist').on('click', function(e) {
            loadBugList('requestee');
        });

        // Requester
        dataSource.requester = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
        dataSource.requester.on('error', function(e) {
            try {
                var response = Y.JSON.parse(e.data.responseText);
                if (response.error)
                    e.error.message = response.error.message;
            } catch(ex) {
                // ignore
            }
        });
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
                emptyMessage: 'No requested flags found.',
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

        Y.one('#requester_refresh').on('click', function(e) {
            updateRequestsTable('requester');
        });
        Y.one('#requester_buglist').on('click', function(e) {
            loadBugList('requester');
        });

        // Initial load
        if (hasReviews) {
            Y.on("contentready", function (e) {
                updateRequestsTable('reviews');
            }, "#reviews_table");
        }
        Y.on("contentready", function (e) {
            updateRequestsTable("requestee");
        }, "#requestee_table");
        Y.on("contentready", function (e) {
            updateRequestsTable("requester");
        }, "#requester_table");
    });
});
