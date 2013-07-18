/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var Dom = YAHOO.util.Dom;
var Event = YAHOO.util.Event;

var REVIEW = {
    widget: false,
    target: false,
    fields: [],
    use_error_for: false,

    init_review_flag: function(fid, flag_name) {
        var idx = this.fields.push({ 'fid': fid, 'flag_name': flag_name, 'component': '' }) - 1;
        this.flag_change(false, idx);
        Event.addListener(fid, 'change', this.flag_change, idx);
    },

    init_mandatory: function() {
        var form = this.find_form();
        if (!form) return;
        Event.addListener(form, 'submit', this.check_mandatory);
        for (var i = 0; i < this.fields.length; i++) {
            var field = this.fields[i];
            // existing reviews that have empty requestee shouldn't force a
            // reviewer to be selected
            field.old_empty_review = Dom.get(field.fid).value == '?'
                && Dom.get(field.flag_name).value == '';
            if (!field.old_empty_review)
                Dom.addClass(field.flag_name, 'required');
        }
    },

    init_enter_bug: function() {
        Event.addListener('component', 'change', REVIEW.component_change);
        BUGZILLA.string['reviewer_required'] = 'A reviewer is required.';
        this.use_error_for = true;
        this.init_create_attachment();
    },

    init_create_attachment: function() {
        Event.addListener('data', 'change', REVIEW.attachment_change);
    },

    component_change: function() {
        for (var i = 0; i < REVIEW.fields.length; i++) {
            REVIEW.flag_change(false, i);
        }
    },

    attachment_change: function() {
        var filename = Dom.get('data').value.split('/').pop().split('\\').pop();
        var description = Dom.get('description');
        if (description.value == '') {
            description.value = filename;
        }
        Dom.get('ispatch').checked =
            REVIEW.endsWith(filename, '.diff') || REVIEW.endsWith(filename, '.patch');
        bz_fireEvent(Dom.get('ispatch'), 'change');
        description.select();
        description.focus();
    },

    flag_change: function(e, field_idx) {
        var field = REVIEW.fields[field_idx];
        var suggestions_span = Dom.get(field.fid + '_suggestions');

        // for requests only
        if (Dom.get(field.fid).value != '?') {
            Dom.addClass(suggestions_span, 'bz_default_hidden');
            return;
        }

        // find selected component
        var component = static_component || Dom.get('component').value;
        if (!component) {
            Dom.addClass(suggestions_span, 'bz_default_hidden');
            return;
        }

        // init menu and events
        if (!field.menu) {
            field.menu = new YAHOO.widget.Menu(field.fid + '_menu');
            field.menu.render(document.body);
            field.menu.subscribe('click', REVIEW.suggestion_click);
            Event.addListener(field.fid + '_suggestions_link', 'click', REVIEW.suggestions_click, field_idx)
        }

        // build review list
        if (field.component != component) {
            field.menu.clearContent();
            if (review_suggestions._mentor) {
                REVIEW.add_menu_item(field_idx, review_suggestions._mentor, true);
            }
            if (review_suggestions[component] && review_suggestions[component].length) {
                REVIEW.add_menu_items(field_idx, review_suggestions[component]);
            } else if (review_suggestions._product) {
                REVIEW.add_menu_items(field_idx, review_suggestions._product);
            }
            field.menu.render();
            field.component = component;
        }

        // show (or hide) the menu
        if (field.menu.getItem(0)) {
            Dom.removeClass(suggestions_span, 'bz_default_hidden');
        } else {
            Dom.addClass(suggestions_span, 'bz_default_hidden');
        }
    },

    add_menu_item: function(field_idx, user, is_mentor) {
        var menu = REVIEW.fields[field_idx].menu;
        var item = menu.addItem(
            { text: user.identity, url: '#' + user.login }
        );
        if (is_mentor)
            item.cfg.setProperty('classname', 'mentor');
    },

    add_menu_items: function(field_idx, users) {
        for (var i = 0; i < users.length; i++) {
            if (!review_suggestions._mentor
                || users[i].login != review_suggestions._mentor.login)
            {
                REVIEW.add_menu_item(field_idx, users[i]);
            }
        }
    },

    suggestions_click: function(e, field_idx) {
        var field = REVIEW.fields[field_idx];
        field.menu.cfg.setProperty('xy', Event.getXY(e));
        field.menu.show();
        Event.stopEvent(e);
        REVIEW.target = field.flag_name;
    },

    suggestion_click: function(type, args) {
        if (args[1]) {
            Dom.get(REVIEW.target).value = decodeURIComponent(args[1].cfg.getProperty('url')).substr(1);
        }
        Event.stopEvent(args[0]);
    },

    check_mandatory: function(e) {
        if (Dom.get('data') && !Dom.get('data').value
            && Dom.get('attach_text') && !Dom.get('attach_text').value)
        {
            return;
        }
        for (var i = 0; i < REVIEW.fields.length; i++) {
            var field = REVIEW.fields[i];
            if (!field.old_empty_review
                && Dom.get(field.fid).value == '?'
                && Dom.get(field.flag_name).value == '')
            {
                if (REVIEW.use_error_for) {
                    _errorFor(Dom.get(REVIEW.fields[i].flag_name), 'reviewer');
                } else {
                    alert('You must provide a reviewer for review requests.');
                }
                Event.stopEvent(e);
            }
        }
    },

    find_form: function() {
        for (var i = 0; i < document.forms.length; i++) {
            var action = document.forms[i].getAttribute('action');
            if (action == 'attachment.cgi' || action == 'post_bug.cgi')
                return document.forms[i];
        }
        return false;
    },

    endsWith: function(str, suffix) {
        return str.indexOf(suffix, str.length - suffix.length) !== -1;
    }
};
