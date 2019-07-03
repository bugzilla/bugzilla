/* The contents of this file are subject to the Mozilla Public
 * License Version 1.1 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy of
 * the License at http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS
 * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * The Original Code is the Bugzilla Bug Tracking System.
 *
 * The Initial Developer of the Original Code is Everything Solved, Inc.
 * Portions created by Everything Solved are Copyright (C) 2010 Everything
 * Solved, Inc. All Rights Reserved.
 *
 * Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>
 */

/* This library assumes that the needed YUI libraries have been loaded
   already. */

YAHOO.bugzilla.dupTable = {
    updateTable: async (dataTable, product_name, summary_field) => {
        if (summary_field.value.length < 4) return;

        dataTable.showTableMessage(dataTable.get("MSG_LOADING"),
                                   YAHOO.widget.DataTable.CLASS_LOADING);
        YAHOO.util.Dom.removeClass('possible_duplicates_container',
                                   'bz_default_hidden');

        let data = {};

        try {
            const { bugs } = await Bugzilla.API.get('bug/possible_duplicates', {
                product: product_name,
                summary: summary_field.value,
                limit: 7,
                include_fields: ['id', 'summary', 'status', 'resolution', 'update_token'],
            });

            data = { results: bugs };
        } catch (ex) {
            data = { error: true };
        }

        dataTable.onDataReturnInitializeTable('', data);
    },
    // This is the keyup event handler. It calls updateTable with a relatively
    // long delay, to allow additional input. However, the delay is short
    // enough that nobody could get from the summary field to the Submit
    // Bug button before the table is shown (which is important, because
    // the showing of the table causes the Submit Bug button to move, and
    // if the table shows at the exact same time as the button is clicked,
    // the click on the button won't register.)
    doUpdateTable: function(e, args) {
        if (e.isComposing) {
          return;
        }

        var dt = args[0];
        var product_name = args[1];
        var summary = YAHOO.util.Event.getTarget(e);
        clearTimeout(YAHOO.bugzilla.dupTable.lastTimeout);
        YAHOO.bugzilla.dupTable.lastTimeout = setTimeout(function() {
            YAHOO.bugzilla.dupTable.updateTable(dt, product_name, summary) },
            600);
    },
    formatBugLink: function(el, oRecord, oColumn, oData) {
        el.innerHTML = `<a href="${BUGZILLA.config.basepath}show_bug.cgi?id=${oData}">${oData}</a>`;
    },
    formatStatus: function(el, oRecord, oColumn, oData) {
        var resolution = oRecord.getData('resolution');
        var bug_status = display_value('bug_status', oData);
        if (resolution) {
            el.innerHTML = bug_status + ' '
                           + display_value('resolution', resolution);
        }
        else {
            el.innerHTML = bug_status;
        }
    },
    formatCcButton: function(el, oRecord, oColumn, oData) {
        var url = `${BUGZILLA.config.basepath}process_bug.cgi?` +
                  `id=${oRecord.getData('id')}&addselfcc=1&token=${escape(oData)}`;
        var button = document.createElement('a');
        button.setAttribute('href',  url);
        button.innerHTML = `<input type="button" value="${YAHOO.bugzilla.dupTable.addCcMessage.htmlEncode()}">`;
        el.appendChild(button);
        new YAHOO.widget.Button(button);
    },
    init: function(data) {
        data.options.initialLoad = false;

        const ds = new YAHOO.util.LocalDataSource([]); // Dummy data source
        const dt = new YAHOO.widget.DataTable(data.container, data.columns, ds, data.options);

        YAHOO.util.Event.on(data.summary_field, 'input', this.doUpdateTable,
                            [dt, data.product_name]);
    }
};
