/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

(function () {
    'use strict';

    YUI.add('bz-review-history', function (Y) {
        function format_duration(o) {
            return moment.duration(o.value).humanize();
        }

        function format_attachment(o) {
            return o.value.description;
        }

        function format_status(o) {
            return o.value;
        }

        function format_setter(o) {
            return o.value.real_name ? o.value.real_name + " <" + o.value.name + ">" : o.value.name;
        }

        function format_date(o) {
            return o.value && Y.DataType.Date.format(o.value, {
                format: "%Y-%m-%d"
            });
        }

        function parse_date(str) {
            var parts = str.split(/\D/);
            return new Date(parts[0], parts[1] - 1, parts[2], parts[3], parts[4], parts[5]);
        }

        var flagDS, bugDS, attachmentDS, historyTable;
        flagDS = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
        flagDS.plug(Y.Plugin.DataSourceJSONSchema, {
            schema: {
                resultListLocator: 'result',
                resultFields: [
                    { key: 'requestee' },
                    { key: 'setter' },
                    { key: 'flag_id' },
                    { key: 'creation_time' },
                    { key: 'status' },
                    { key: 'bug_id' },
                    { key: 'type' },
                    { key: 'attachment_id' }
                ]
            }
        });

        bugDS = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
        bugDS.plug(Y.Plugin.DataSourceJSONSchema, {
            schema: {
                resultListLocator: 'result.bugs',
                resultFields: [
                    { key: 'id' },
                    { key: 'summary' }
                ]
            }
        });

        attachmentDS = new Y.DataSource.IO({ source: 'jsonrpc.cgi' });
        attachmentDS.plug(Y.Plugin.DataSourceJSONSchema, {
            schema: {
                metaFields: { 'attachments': 'result.attachments' }
            }
        });

        historyTable = new Y.DataTable({
            columns: [
                { key: 'creation_time', label: 'Created', sortable: true, formatter: format_date },
                { key: 'attachment', label: 'Attachment', formatter: format_attachment, allowHTML: true },
                { key: 'setter', label: 'Requester', formatter: format_setter },
                { key: "status", label: "Status", sortable: true, allowHTML: true, formatter: format_status },
                { key: "duration", label: "Duration", sortable: true, formatter: format_duration },
                { key: "bug_id", label: "Bug", sortable: true, allowHTML: true,
                  formatter: '<a href="show_bug.cgi?id={value}" target="_blank">{value}</a>' },
                { key: 'bug_summary', label: 'Summary' }
            ]
        });

        function fetch_flag_ids(user) {
            return new Y.Promise(function (resolve, reject) {
                var flagIdCallback = {
                    success: function (e) {
                        var flags = e.response.results;
                        var flag_ids = flags.filter(function (flag) {
                            return flag.status === '?';
                        })
                        .map(function (flag) {
                            return flag.flag_id;
                        });

                        if (flag_ids.length > 0) {
                            resolve(flag_ids);
                        } else {
                            reject("No reviews found");
                        }
                    },
                    failure: function (e) {
                        reject(e.error.message);
                    }
                };

                flagDS.sendRequest({
                    request: Y.JSON.stringify({
                        version: '1.1',
                        method: 'Review.flag_activity',
                        params: {
                            type_name: 'review',
                            requestee: user,
                            include_fields: ['flag_id', 'status']
                        }
                    }),
                    cfg: {
                        method: "POST",
                        headers: { 'Content-Type': 'application/json' }
                    },
                    callback: flagIdCallback
                });
            });
        }

        function fetch_flags(flag_ids) {
            return new Y.Promise(function (resolve, reject) {
                flagDS.sendRequest({
                    request: Y.JSON.stringify({
                        version: '1.1',
                        method: 'Review.flag_activity',
                        params: { flag_ids: flag_ids }
                    }),
                    cfg: {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' }
                    },
                    callback: {
                        success: function (e) {
                            resolve(e.response.results);
                        },
                        failure: function (e) {
                            reject(e.error.message);
                        }
                    }
                });
            });
        }

        function fetch_bug_summaries(flags) {
            return new Y.Promise(function (resolve, reject) {
                var bug_ids = Y.Array.dedupe(flags.map(function (f) {
                    return f.bug_id;
                }));

                bugDS.sendRequest({
                    request: Y.JSON.stringify({
                        version: '1.1',
                        method: 'Bug.get',
                        params: { ids: bug_ids, include_fields: ['summary', 'id'] }
                    }),
                    cfg: {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' }
                    },
                    callback: {
                        success: function (e) {
                            var bugs = e.response.results,
                                summary = {};

                            bugs.forEach(function (bug) {
                                summary[bug.id] = bug.summary;
                            });
                            flags.forEach(function (flag) {
                                flag.bug_summary = summary[flag.bug_id];
                            });
                            resolve(flags);
                        },
                        failure: function (e) {
                            reject(e.error.message);
                        }
                    }
                });
            });
        }

        function fetch_attachment_descriptions(flags) {
            return new Y.Promise(function (resolve, reject) {
                var attachment_ids = Y.Array.dedupe(flags.map(function (f) {
                    return f.attachment_id;
                }));

                attachmentDS.sendRequest({
                    request: Y.JSON.stringify({
                        version: '1.1',
                        method: 'Bug.attachments',
                        params: {
                            attachment_ids: attachment_ids,
                            include_fields: ['id', 'description']
                        }
                    }),
                    cfg: {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' }
                    },
                    callback: {
                        success: function (e) {
                            var attachments = e.response.meta.attachments;
                            flags.forEach(function (flag) {
                                flag.attachment = attachments[flag.attachment_id];
                            });
                            resolve(flags);
                        },
                        failure: function (e) {
                            reject(e.error.message);
                        }
                    }
                });
            });
        }

        function generate_history(flags) {
            var history = [],
                stash = {},
                i = 1, stash_key;

            flags.forEach(function (flag) {
                var flag_id = flag.flag_id;

                switch (flag.status) {
                    case '?':
                        if (stash[flag_id]) {
                            stash["#" + i] = stash[flag_id];
                            i = i + 1;
                        }

                        stash[flag_id] = {
                            setter: flag.setter,
                            bug_id: flag.bug_id,
                            bug_summary: flag.bug_summary,
                            attachment: flag.attachment,
                            start: parse_date(flag.creation_time),
                            creation_time: parse_date(flag.creation_time)
                        };
                        break;

                    case '+':
                    case '-':
                        if (stash[flag_id]) {
                            history.push({
                                setter: stash[flag_id].setter,
                                bug_id: stash[flag_id].bug_id,
                                bug_summary: stash[flag_id].bug_summary,
                                attachment: stash[flag_id].attachment,
                                status: 'review' + flag.status,
                                duration: parse_date(flag.creation_time) - stash[flag_id].start,
                                creation_time: stash[flag_id].creation_time
                            });
                            stash[flag_id] = null;
                        }
                        break;
                }
            });
            for (stash_key in stash) {
                if (stash[stash_key]) {
                    history.push({
                        setter: stash[stash_key].setter,
                        bug_id: stash[stash_key].bug_id,
                        bug_summary: stash[stash_key].bug_summary,
                        attachment: stash[stash_key].attachment,
                        creation_time: stash[stash_key].creation_time,
                        status: 'review?',
                        duration: new Date() - stash[stash_key].creation_time
                    });
                }
            }

            return history;
        }

        Y.ReviewHistory = {};

        Y.ReviewHistory.render = function (sel) {
            Y.one('#history-loading').hide();
            historyTable.render(sel);
            historyTable.setAttrs({
                width: "100%"
            }, true);
        };

        Y.ReviewHistory.refresh = function (user, real_name) {
            var caption = "Review History for " + (real_name ? real_name + ' &lt;' + user + '&gt;' : user);
            historyTable.setAttrs({
                caption: caption
            });
            historyTable.set('data', null);
            historyTable.showMessage('Loading...');
            fetch_flag_ids(user)
            .then(fetch_flags)
            .then(fetch_bug_summaries)
            .then(fetch_attachment_descriptions)
            .then(generate_history)
            .then(function (history) {
                historyTable.set('data', history);
                historyTable.sort({
                    creation_time: 'asc'
                });
            }, function (message) {
                historyTable.showMessage(message);
            });
        };

    }, '0.0.1', {
        requires: [
            "node", "datatype-date", "datatable", "datatable-sort", "datatable-message", "json-stringify",
            "datatable-datasource", "datasource-io", "datasource-jsonschema", "cookie",
            "gallery-datatable-row-expansion-bmo", "handlebars", "escape", "promise"
        ]
    });
}());
