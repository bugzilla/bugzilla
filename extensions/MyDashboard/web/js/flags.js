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
    }).use('node', 'datatable', 'datatable-sort', 'escape', function(Y) {
        // Common
        var dataTable = {
            requestee: null,
            requester: null
        };

        var updateFlagTable = async type => {
            if (!type) return;

            Y.one('#' + type + '_loading').removeClass('bz_default_hidden');
            Y.one('#' + type + '_count_refresh').addClass('bz_default_hidden');

            dataTable[type].set('data', []);
            dataTable[type].render("#" + type + "_table");
            dataTable[type].showMessage('loadingMessage');

            try {
                const { result } = await Bugzilla.API.get('mydashboard/run_flag_query', { type });
                const results = result[type];

                Y.one(`#${type}_loading`).addClass('bz_default_hidden');
                Y.one(`#${type}_count_refresh`).removeClass('bz_default_hidden');
                Y.one(`#${type}_flags_found`)
                    .setHTML(`${results.length} ${(results.length === 1 ? 'request' : 'requests')} found`);

                dataTable[type].set('data', results);
                dataTable[type].render(`#${type}_table`);
            } catch ({ message }) {
                Y.one(`#${type}_loading`).addClass('bz_default_hidden');
                Y.one(`#${type}_count_refresh`).removeClass('bz_default_hidden');

                dataTable[type].showMessage(`Failed to load requests.`);
            }
        };

        var loadBugList = function(type) {
            if (!type) return;
            var data = dataTable[type].data;
            var ids = [];
            for (var i = 0, l = data.size(); i < l; i++) {
                ids.push(data.item(i).get('bug_id'));
            }
            var url = `${BUGZILLA.config.basepath}buglist.cgi?bug_id=${ids.join('%2C')}`;
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
            return `<a href="${BUGZILLA.config.basepath}show_bug.cgi?id=${encodeURIComponent(o.data.bug_id)}" ` +
                   `target="_blank" title="${o.data.bug_status.htmlEncode()} - ${o.data.bug_summary.htmlEncode()}" ` +
                   `class="${bug_closed}">${o.data.bug_id}</a>`;
        };

        var updatedFormatter = function(o) {
            return '<span title="' + o.value.htmlEncode() + '">' +
                o.data.updated_fancy.htmlEncode() + '</span>';
        };

        var requesteeFormatter = function(o) {
            return o.value.htmlEncode();
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
                    o.value.htmlEncode() + '</a>';
            }
            else {
                return o.value.htmlEncode();
            }
        };

        // Requestee
        dataTable.requestee = new Y.DataTable({
            columns: [
                { key: "requester", label: "Requester", sortable: true },
                { key: "type", label: "Type", sortable: true,
                formatter: flagNameFormatter, allowHTML: true },
                { key: "bug_id", label: "Bug", sortable: true,
                formatter: bugLinkFormatter, allowHTML: true },
                { key: "updated", label: "Updated", sortable: true,
                formatter: updatedFormatter, allowHTML: true }
            ],
            strings: {
                emptyMessage: 'No requests found.',
            }
        });

        dataTable.requestee.plug(Y.Plugin.DataTableSort);

        Y.one('#requestee_refresh').on('click', function(e) {
            updateFlagTable('requestee');
        });
        Y.one('#requestee_buglist').on('click', function(e) {
            loadBugList('requestee');
        });

        // Requester
        dataTable.requester = new Y.DataTable({
            columns: [
                { key:"requestee", label:"Requestee", sortable:true,
                formatter: requesteeFormatter, allowHTML: true },
                { key:"type", label:"Type", sortable:true,
                formatter: flagNameFormatter, allowHTML: true },
                { key:"bug_id", label:"Bug", sortable:true,
                formatter: bugLinkFormatter, allowHTML: true },
                { key: "updated", label: "Updated", sortable: true,
                formatter: updatedFormatter, allowHTML: true }
            ],
            strings: {
                emptyMessage: 'No requests found.',
            }
        });

        dataTable.requester.plug(Y.Plugin.DataTableSort);

        Y.one('#requester_refresh').on('click', function(e) {
            updateFlagTable('requester');
        });
        Y.one('#requester_buglist').on('click', function(e) {
            loadBugList('requester');
        });

        // Initial load
        Y.on("contentready", function (e) {
            updateFlagTable("requestee");
            setInterval(function(e) {
                updateFlagTable("requestee");
            },1000*60*10);
        }, "#requestee_table");
        Y.on("contentready", function (e) {
            updateFlagTable("requester");
            setInterval(function(e) {
                updateFlagTable("requester");
            },1000*60*10);
        }, "#requester_table");
    });
});
