/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var REVIEW = {
    widget: false,
    target: false,
    fields: [],
    use_error_for: false,

    init_review_flag: function(fid, flag_name) {
        var idx = this.fields.push({ 'fid': fid, 'flag_name': flag_name, 'component': '' }) - 1;
        this.flag_change({ data: idx });
        $('#' + fid).on('change', null, idx, this.flag_change);
    },

    init_mandatory: function() {
        var form = this.find_form();
        if (!form) return;
        $(form).on('submit', this.check_mandatory);
        for (var i = 0; i < this.fields.length; i++) {
            var field = this.fields[i];
            // existing reviews that have empty requestee shouldn't force a
            // reviewer to be selected
            field.old_empty_review = $('#' + field.fid).val() == '?'
                && $('#' + field.flag_name).val() == '';
            if (!field.old_empty_review)
                $('#' + field.flag_name).addClass('required');
        }
    },

    init_enter_bug: function() {
        $('#component').on('change', REVIEW.component_change);
        BUGZILLA.string['reviewer_required'] = 'A reviewer is required.';
        this.use_error_for = true;
    },

    component_change: function() {
        for (var i = 0; i < REVIEW.fields.length; i++) {
            REVIEW.flag_change({ data: i });
        }
    },

    flag_change: function(e) {
        var field = REVIEW.fields[e.data];
        var suggestions_span = $('#' + field.fid + '_suggestions');

        // for requests only
        if ($('#' + field.fid).val() != '?') {
            suggestions_span.hide();
            return;
        }

        // find selected component
        var component = static_component || $('#component').val();
        if (!component) {
            suggestions_span.hide();
            return;
        }

        // add the menu
        if (field.component != component) {
            var items = [];
            for (var i = 0, il = review_suggestions._mentors.length; i < il; i++) {
                REVIEW.add_menu_item(items, review_suggestions._mentors[i], true);
            }
            if (review_suggestions[component] && review_suggestions[component].length) {
                REVIEW.add_menu_items(items, review_suggestions[component]);
            }
            else if (review_suggestions._product) {
                REVIEW.add_menu_items(items, review_suggestions._product);
            }
            if (items.length) {
                suggestions_span.show();
                $.contextMenu('destroy', '#' + field.fid + '_suggestions');
                $.contextMenu({
                    selector: '#' + field.fid + '_suggestions',
                    trigger: 'left',
                    events: {
                        show: function() {
                            REVIEW.target = $('#' + field.flag_name);
                        }
                    },
                    items: items
                });
            }
            else {
                suggestions_span.hide();
            }
        }
    },

    add_menu_item: function(items, user, is_mentor) {
        for (var i = 0, il = items.length; i < il; i++) {
            if (items[i].login == user.login)
                return;
        }

        var queue = '';
        if (user.review_count == 0) {
            queue = 'empty queue';
        } else {
            queue = user.review_count + ' review' + (user.review_count == 1 ? '' : 's') + ' in queue';
        }

        items.push({
            name: user.identity + ' (' + queue + ')',
            login: user.login,
            className: (is_mentor ? 'mentor' : ''),
            callback: function() {
                REVIEW.target.val(user.login);
            }
        });
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

    check_mandatory: function(e) {
        if ($('#file').length && !$('#file').val()
            && $('#att-textarea').length && !$('#att-textarea').val())
        {
            return;
        }
        for (var i = 0; i < REVIEW.fields.length; i++) {
            var field = REVIEW.fields[i];
            if (!field.old_empty_review
                && $('#' + field.fid).val() == '?'
                && $('#' + field.flag_name).val() == '')
            {
                if (REVIEW.use_error_for) {
                    _errorFor($('#' + REVIEW.fields[i].flag_name)[0], 'reviewer');
                } else {
                    alert('You must provide a reviewer for review requests.');
                }
                e.preventDefault();
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
