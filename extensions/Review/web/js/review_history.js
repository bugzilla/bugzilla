/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function () {
    'use strict';

    YUI.add('bz-review-history', function (Y) {
        function format_duration(o) {
            if (o.value) {
                if (o.value < 0) {
                    return "???";
                } else {
                    return moment.duration(o.value).humanize();
                }
            }
            else {
                return "---";
            }
        }

        function format_attachment(o) {
            if (o.value) {
                return o.value.description;
            }
        }

        function format_action(o) {
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

        const historyTable = new Y.DataTable({
            columns: [
                { key: 'creation_time', label: 'Created', sortable: true, formatter: format_date },
                { key: 'attachment', label: 'Attachment', formatter: format_attachment },
                { key: 'setter', label: 'Requester', formatter: format_setter },
                { key: "action", label: "Action", sortable: true,  formatter: format_action },
                { key: "duration", label: "Duration", sortable: true, formatter: format_duration },
                { key: "bug_id", label: "Bug", sortable: true, allowHTML: true,
                  formatter: `<a href="${BUGZILLA.config.basepath}show_bug.cgi?id={value}" target="_blank">{value}</a>` },
                { key: 'bug_summary', label: 'Summary' }
            ]
        });

        const fetch_flags = async user => {
            try {
                const data = await Bugzilla.API.get('review/flag_activity', { type_name: 'review', requestee: user });
                const flags = data.filter(flag => flag.status === '?');

                if (!flags.length) {
                    return Promise.reject("No reviews found");
                }

                flags.forEach(flag => flag.creation_time = parse_date(flag.creation_time));
                flags.sort((a, b) => a.id > b.id ? 1 : a.id < b.id ? -1 : 0);

                return Promise.resolve(flags);
            } catch ({ message }) {
                return Promise.reject(message);
            }
        }

        const fetch_bug_summaries = async flags => {
            const bug_ids = [...(new Set(flags.map(flag => flag.bug_id)))]; // remove duplicates with `Set`
            const summary = {};

            try {
                const { bugs } = await Bugzilla.API.get('bug', { id: bug_ids, include_fields: ['id', 'summary'] });

                bugs.forEach(bug => summary[bug.id] = bug.summary);
                flags.forEach(flag => flag.bug_summary = summary[flag.bug_id]);

                return Promise.resolve(flags);
            } catch ({ message }) {
                return Promise.reject(message);
            }
        }

        const fetch_attachment_descriptions = async flags => {
            const attachment_ids = [...(new Set(flags.map(flag => flag.attachment_id)))]; // remove duplicates

            try {
                const { attachments } = await Bugzilla.API.get(`bug/attachment/${attachment_ids[0]}`, {
                    attachment_ids,
                    include_fields: ['id', 'description'],
                });

                flags.forEach(flag => flag.attachment = attachments[flag.attachment_id]);

                return Promise.resolve(flags);
            } catch ({ message }) {
                return Promise.reject(message);
            }
        }

        function add_historical_action(history, flag, stash, action) {
            history.push({
                attachment:    flag.attachment,
                bug_id:        flag.bug_id,
                bug_summary:   flag.bug_summary,
                creation_time: stash.creation_time,
                duration:      flag.creation_time - stash.creation_time,
                setter:        stash.setter,
                action:        action
            });
        }

        function generate_history(flags, user) {
            var history = [],
                stash   = {},
                flag, stash_key ;

            flags.forEach(function (flag) {
                var flag_id = flag.flag_id;

                switch (flag.status) {
                    case '?':
                        // If we get a ? after a + or -, we get a fresh start.
                        if (stash[flag_id] && stash[flag_id].is_complete)
                            delete stash[flag_id];

                        // handle untargeted review requests.
                        if (!flag.requestee)
                            flag.requestee = { id: 'the wind', name: 'the wind' };

                        if (stash[flag_id]) {
                            // flag was reassigned
                            if (flag.requestee.id != stash[flag_id].requestee.id) {
                                // if ? started out mine, but went to someone else.
                                if (stash[flag_id].requestee.name == user) {
                                    add_historical_action(history, flag, stash[flag_id], 'reassigned to ' + flag.requestee.name);
                                    stash[flag_id] = flag;
                                }
                                else {
                                    // flag changed hands. Reset the creation_time and requestee
                                    stash[flag_id].creation_time = flag.creation_time;
                                    stash[flag_id].requestee     = flag.requestee;
                                }
                            }
                        } else {
                            stash[flag_id] = flag;
                        }
                        break;

                    case 'X':
                        if (stash[flag_id]) {
                            // Only process if we did not get a + or a - since
                            if (!stash[flag_id].is_complete) {
                                add_historical_action(history, flag, stash[flag_id], 'cancelled');
                            }
                            delete stash[flag_id];
                        }
                        break;


                    case '+':
                    case '-':
                        // if we get a + or -, we only accept it if the requestee is the user we're interested in.
                        // we set is_complete to handle cancelations.
                        if (stash[flag_id] && stash[flag_id].requestee.name == user) {
                            add_historical_action(history, flag, stash[flag_id], "review" + flag.status);
                            stash[flag_id].is_complete = true;
                        }
                        break;
                }
            });

            for (stash_key in stash) {
                flag = stash[stash_key];
                if (flag.is_complete) continue;
                if (flag.requestee.name != user) continue;
                history.push({
                    attachment:    flag.attachment,
                    bug_id:        flag.bug_id,
                    bug_summary:   flag.bug_summary,
                    creation_time: flag.creation_time,
                    duration:      new Date() - flag.creation_time,
                    setter:        flag.setter,
                    action:        'review?'
                });
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
            fetch_flags(user)
            .then(fetch_bug_summaries)
            .then(fetch_attachment_descriptions)
            .then(function (flags) {
                return new Promise((resolve, reject) => {
                    try {
                        resolve(generate_history(flags, user));
                    }
                    catch (e) {
                        reject(e.message);
                    }
                });
            })
            .then(function (history) {
                historyTable.set('data', history);
                historyTable.sort({
                    creation_time: 'desc'
                });
            }, function (message) {
                historyTable.showMessage(message);
            });
        };

    }, '0.0.1', {
        requires: [
            'node', 'datatype-date', 'datatable', 'datatable-sort', 'datatable-message', 'cookie',
            'gallery-datatable-row-expansion-bmo', 'handlebars'
        ]
    });
});
