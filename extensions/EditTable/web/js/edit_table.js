/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */


function EditTable(parent_el, table_data) {
    this.parent_el = YAHOO.util.Dom.get(parent_el);
    this.table_data = table_data;
    this.field_count = table_data.fields.length;
    if (!JSON) JSON = YAHOO.lang.JSON;

    this.render = function() {
        // create table
        this.parent_el.innerHTML = '';
        var table = document.createElement('table');

        // header
        var tr = document.createElement('tr');
        for (var i = 0; i < this.field_count; i++) {
            var th = document.createElement('th');
            th.appendChild(document.createTextNode(this.table_data.fields[i]));
            tr.appendChild(th);
        }
        var td = document.createElement('td');
        td.innerHTML = '&nbsp;&nbsp;';
        tr.appendChild(td);
        table.appendChild(tr);

        // rows
        for (var i = 0; i < table_data.data.length; i++) {
            // skip deleted rows
            if (this.table_data.data[i][0] < 0)
                continue;
            var tr = document.createElement('tr');
            for (var j = 0; j < this.field_count; j++) {
                var td = document.createElement('td');
                td.appendChild(document.createTextNode(this.table_data.data[i][j]));
                tr.appendChild(td);

                if (this.table_data.fields[j] != this.table_data.id_field) {
                    td.className = 'editable';
                    td.contentEditable = true;
                    YAHOO.util.Event.addListener(td, 'keydown', this._edit_keydown, this);
                    YAHOO.util.Event.addListener(td, 'blur', this._save, this);
                    d = td;
                }
            }
            var td = document.createElement('td');
            var a = document.createElement('a');
            a.href = '#';
            a.innerHTML = 'x';
            YAHOO.util.Event.addListener(a, 'click', this._remove_row, this);
            td.appendChild(a);
            td.className = 'action';
            tr.appendChild(td);
            table.appendChild(tr);
        }

        this.parent_el.appendChild(table);

        var add_btn = document.createElement('button');
        add_btn.innerHTML = 'Add';
        YAHOO.util.Event.addListener(add_btn, 'click', this._add_row, this);
        this.parent_el.appendChild(add_btn);
    },

    this.to_json = function(target) {
        YAHOO.util.Dom.get(target).value = JSON.stringify(this.table_data);
    },

    this._add_row = function(event, obj) {
        var row = [];
        for (var i = 0; i < obj.field_count; i++) {
            row.push(obj.table_data.fields[i] == obj.table_data.id_field ? '-' : '');
        }
        obj.table_data.data.push(row);
        obj.render();
        YAHOO.util.Dom.removeClass('commit_btn', 'bz_default_hidden');
        event.preventDefault();
    },

    this._remove_row = function(event, obj) {
        var row = event.target.parentElement.parentElement.rowIndex - 1;
        if (obj.table_data.data[row][0] == '-') {
            // removing a newly added row
            obj.table_data.data.splice(row, 1);
        }
        else {
            // to remove a db row we set its id to negative
            // it'll be skipped by render, and the update script knows which id to delete
            obj.table_data.data[row][0] = -obj.table_data.data[row][0];
        }
        obj.render();
        YAHOO.util.Dom.removeClass('commit_btn', 'bz_default_hidden');
        event.preventDefault();
    },

    this._save = function(event, obj) {
        var row = event.target.parentElement.rowIndex - 1;
        var col = event.target.cellIndex;
        var value = event.target.textContent;
        if (obj.table_data.data[row][col] != event.target.textContent) {
            obj.table_data.data[row][col] = event.target.textContent;
            YAHOO.util.Dom.removeClass('commit_btn', 'bz_default_hidden');
        }
    },

    this._revert = function(event, obj) {
        var row = event.target.parentElement.rowIndex - 1;
        var col = event.target.cellIndex;
        event.target.replaceChild(
            document.createTextNode(obj.table_data.data[row][col]),
            event.target.firstChild
        );
    },

    this._edit_keydown = function(event, obj) {
        if (event.keyCode == 13) {
            event.preventDefault();
            obj._save(event, obj);
            document.activeElement.blur(event.target);
        }
        else if (event.keyCode == 27) {
            event.preventDefault();
            obj._revert(event, obj);
        }
    }
};
