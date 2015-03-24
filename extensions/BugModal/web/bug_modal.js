/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    'use strict';

    // all keywords for autocompletion (lazy-loaded on edit)
    var keywords = [];

    // products with descriptions (also lazy-loaded)
    var products = [];

    // scroll to an element
    function scroll_to(el, complete) {
        var offset = el.offset();
        $('html, body')
            .animate({
                    scrollTop: offset.top - 20,
                    scrollLeft: offset.left = 20
                },
                200,
                complete
            );
    }

    // expand all modules
    $('#expand-all-btn')
        .click(function(event) {
            event.preventDefault();
            var btn = $(event.target);
            if (btn.data('expanded-modules')) {
                btn.data('expanded-modules').slideToggle(200, 'swing', function() {
                    btn.data('expanded-spinners').html('&#9656;');
                });
                btn.data('expanded-modules', false);
                btn.text('Expand All');
            }
            else {
                var modules = $('.module-content:hidden');
                var spinners = $([]);
                modules.each(function() {
                    spinners.push($(this).parent('.module').find('.module-spinner')[0]);
                });
                btn.data('expanded-modules', modules);
                btn.data('expanded-spinners', spinners);
                modules.slideToggle(200, 'swing', function() {
                    spinners.html('&#9662;');
                });
                btn.text('Collapse');
            }
        });

    // expand/colapse module
    $('.module-header')
        .click(function(event) {
            event.preventDefault();
            var target = $(event.target);
            var latch = target.hasClass('module-header') ? target.children('.module-latch') : target.parent('.module-latch');
            var spinner = $(latch.children('.module-spinner')[0]);
            var module = $(latch.parents('.module')[0]);
            var content = $(module.children('.module-content')[0]);
            content.slideToggle(200, 'swing', function() {
                spinner.html(content.is(':visible') ? '&#9662;' : '&#9656;');
            });
        });

    // toggle obsolete attachments
    $('#attachments-obsolete-btn')
        .click(function(event) {
            event.preventDefault();
            $(event.target).text(($('#attachments tr:hidden').length ? 'Hide' : 'Show') + ' Obsolete Attachments');
            $('#attachments tr.attach-obsolete').toggle();
        });

    // comment collapse/expand
    $('.comment-spinner')
        .click(function(event) {
            event.preventDefault();
            var spinner = $(event.target);
            var id = spinner.attr('id').match(/\d+$/)[0];
            // switch to full header for initially collapsed comments
            if (spinner.attr('id').match(/^ccs-/)) {
                $('#cc-' + id).hide();
                $('#ch-' + id).show();
            }
            $('#ct-' + id).slideToggle('fast', function() {
                $('#c' + id).find('.activity').toggle();
                spinner.text($('#ct-' + id + ':visible').length ? '-' : '+');
            });
        });

    // url --> unsafe warning
    $('.unsafe-url')
        .click(function(event) {
            event.preventDefault();
            if (confirm('This is considered an unsafe URL and could possibly be harmful. ' +
                        'The full URL is:\n\n' + $(event.target).attr('title') + '\n\nContinue?'))
            {
                try {
                    window.open($(event.target).attr('title'));
                } catch(ex) {
                    alert('Malformed URL');
                }
            }
        });

    // last comment btn
    $('#last-comment-btn')
        .click(function(event) {
            event.preventDefault();
            var id = $('.comment:last')[0].parentNode.id;
            scroll_to($('#' + id));
            window.location.hash = id;
        });

    // top btn
    $('#top-btn')
        .click(function(event) {
            event.preventDefault();
            scroll_to($('body'));
        });

    // use non-native tooltips for relative times and bug summaries
    $('.rel-time, .bz_bug_link').tooltip({
        position: { my: "left top+8", at: "left bottom", collision: "flipfit" },
        show: { effect: 'none' },
        hide: { effect: 'none' }
    });

    // tooltips create a new ui-helper-hidden-accessible div each time a
    // tooltip is shown.  this is never removed leading to memory leak and
    // bloated dom.  http://bugs.jqueryui.com/ticket/10689
    $('.ui-helper-hidden-accessible').remove();

    // product/component info
    $('.spin-toggle')
        .click(function(event) {
            event.preventDefault();
            var latch = $($(event.target).data('latch'));
            var el_for = $($(event.target).data('for'));

            if (latch.data('expanded')) {
                latch.data('expanded', false).html('&#9656;');
                el_for.hide();
            }
            else {
                latch.data('expanded', true).html('&#9662;');
                el_for.show();
            }
        });

    // cc list
    $('#cc-latch, #cc-summary')
        .click(function(event) {
            event.preventDefault();
            var latch = $('#cc-latch');

            if (latch.data('expanded')) {
                latch.data('expanded', false).html('&#9656;');
                $('#cc-list').hide();
            }
            else {
                latch.data('expanded', true).html('&#9662;');
                $('#cc-list').show();
                if (!latch.data('fetched')) {
                    $('#cc-list').html(
                        '<img src="extensions/BugModal/web/throbber.gif" width="16" height="11"> Loading...'
                    );
                    bugzilla_ajax(
                        {
                            url: 'rest/bug_modal/cc/' + BUGZILLA.bug_id
                        },
                        function(data) {
                            $('#cc-list').html(data.html);
                            latch.data('fetched', true);
                        }
                    );
                }
            }
        });

    // copy summary to clipboard
    if ($('#copy-summary').length) {
        var zero = new ZeroClipboard($('#copy-summary'));
        zero.on({
            'error': function(event) {
                console.log(event.message);
                zero.destroy();
                $('#copy-summary').hide();

            },
            'copy': function(event) {
                var clipboard = event.clipboardData;
                clipboard.setData('text/plain', 'Bug ' + BUGZILLA.bug_id + ' - ' + $('#field-value-short_desc').text());
            }
        });
    }

    //
    // anything after this point is only executed for logged in users
    //

    if (BUGZILLA.user.id === 0) return;

    // edit/save mode button
    $('#mode-btn')
        .click(function(event) {
            event.preventDefault();

            // hide buttons, old error messages
            $('#mode-btn-readonly').hide();

            // toggle visibility
            $('.edit-hide').hide();
            $('.edit-show').show();

            // expand specific modules
            $('#module-details .module-header').each(function() {
                if ($(this.parentNode).find('.module-content:visible').length === 0) {
                    $(this).click();
                }
            });

            // if there's no current user-story, it's a better experience if it's editable by default
            if ($('#cf_user_story').val() === '') {
                $('#user-story-edit-btn').click();
            }

            // "loading.." ui
            $('#mode-btn-loading').show();
            $('#cancel-btn').prop('disabled', true);
            $('#mode-btn').prop('disabled', true);

            // load the missing select data
            bugzilla_ajax(
                {
                    url: 'rest/bug_modal/edit/' + BUGZILLA.bug_id
                },
                function(data) {
                    $('#mode-btn').hide();

                    // populate select menus
                    $.each(data.options, function(key, value) {
                        var el = $('#' + key);
                        if (!el) return;
                        var selected = el.val();
                        el.empty();
                        $(value).each(function(i, v) {
                            el.append($('<option>', { value: v.name, text: v.name }));
                        });
                        el.val(selected);
                        if (el.attr('multiple') && value.length < 5) {
                            el.attr('size', value.length);
                        }
                    });

                    // build our product description hash
                    $.each(data.options.product, function() {
                        products[this.name] = this.description;
                    });

                    // keywords is a multi-value autocomplete
                    // (this should probably be a simple jquery plugin)
                    keywords = data.keywords;
                    $('#keywords')
                        .bind('keydown', function(event) {
                            if (event.keyCode == $.ui.keyCode.TAB && $(this).autocomplete('instance').menu.active)
                            {
                                event.preventDefault();
                            }
                        })
                        .blur(function() {
                            $(this).val($(this).val().replace(/,\s*$/, ''));
                        })
                        .autocomplete({
                            source: function(request, response) {
                                response($.ui.autocomplete.filter(keywords, request.term.split(/,\s*/).pop()));
                            },
                            focus: function() {
                                return false;
                            },
                            select: function(event, ui) {
                                var terms = this.value.split(/,\s*/);
                                terms.pop();
                                terms.push(ui.item.value);
                                terms.push('');
                                this.value = terms.join(', ');
                                return false;
                            }
                        });

                    $('#cancel-btn').prop('disabled', false);
                    $('#top-save-btn').show();
                    $('#cancel-btn').show();
                    $('#commit-btn').show();
                },
                function() {
                    $('#mode-btn-readonly').show();
                    $('#mode-btn-loading').hide();
                    $('#mode-btn').prop('disabled', false);
                    $('#mode-btn').show();
                    $('#cancel-btn').hide();
                    $('#commit-btn').hide();

                    $('.edit-show').hide();
                    $('.edit-hide').show();
                }
            );
        });
    $('#mode-btn').prop('disabled', false);

    // cc add/remove
    $('#cc-btn')
        .click(function(event) {
            event.preventDefault();
            var is_cced = $(event.target).data('is-cced') == '1';

            var cc_change;
            if (is_cced) {
                cc_change = { remove: [ BUGZILLA.user.login ] };
                $('#cc-btn')
                    .text('Follow')
                    .data('is-cced', '0')
                    .prop('disabled', true);
            }
            else {
                cc_change = { add: [ BUGZILLA.user.login ] };
                $('#cc-btn')
                    .text('Stop following')
                    .data('is-cced', '1')
                    .prop('disabled', true);
            }

            bugzilla_ajax(
                {
                    url: 'rest/bug/' + BUGZILLA.bug_id,
                    type: 'PUT',
                    data: JSON.stringify({ cc: cc_change })
                },
                function(data) {
                    $('#cc-btn').prop('disabled', false);
                    if (!(data.bugs[0].changes && data.bugs[0].changes.cc))
                        return;
                    if (data.bugs[0].changes.cc.added == BUGZILLA.user.login) {
                        $('#cc-btn')
                            .text('Stop following')
                            .data('is-cced', '1');
                    }
                    else if (data.bugs[0].changes.cc.removed == BUGZILLA.user.login) {
                        $('#cc-btn')
                            .text('Follow')
                            .data('is-cced', '0');
                    }
                },
                function(message) {
                    $('#cc-btn').prop('disabled', false);
                }
            );

        });

    // cancel button, reset the ui back to read-only state
    // for now, do this with a redirect to self
    // ideally this should revert all field back to their initially loaded
    // values and switch the ui back to read-only mode without the redirect
    $('#cancel-btn')
        .click(function(event) {
            event.preventDefault();
            window.location.replace($('#this-bug').val());
        });

    // top comment button, scroll the textarea into view
    $('.comment-btn')
        .click(function(event) {
            event.preventDefault();
            // focus first to grow the textarea, so we scroll to the correct location
            $('#comment').focus();
            scroll_to($('#bottom-save-btn'));
        });

    // needinfo in people section -> scroll to near-comment ui
    $('#needinfo-scroll')
        .click(function(event) {
            event.preventDefault();
            scroll_to($('#needinfo_role'), function() { $('#needinfo_role').focus(); });
        });

    // knob
    $('#bug_status')
        .change(function(event) {
            if (event.target.value == "RESOLVED" || event.target.value == "VERIFIED") {
                $('#resolution').change().show();
            }
            else {
                $('#resolution').hide();
                $('#duplicate-container').hide();
                $('#mark-as-dup-btn').show();
            }
        })
        .change();
    $('#resolution')
        .change(function(event) {
            if (event.target.value == "DUPLICATE") {
                $('#duplicate-container').show();
                $('#mark-as-dup-btn').hide();
                $('#dup_id').focus();
            }
            else {
                $('#duplicate-container').hide();
                $('#mark-as-dup-btn').show();
            }
        })
        .change();
    $('#mark-as-dup-btn')
        .click(function(event) {
            event.preventDefault();
            $('#bug_status').val('RESOLVED').change();
            $('#resolution').val('DUPLICATE').change();
            $('#dup_id').focus();
        });

    // add see-also button
    $('.bug-urls-btn')
        .click(function(event) {
            event.preventDefault();
            var name = event.target.id.replace(/-btn$/, '');
            $(event.target).hide();
            $('#' + name).show().focus();
        });

    // bug flag value <select>
    $('.bug-flag')
        .change(function(event) {
            var target = $(event.target);
            var id = target.prop('id').replace(/^flag(_type)?-(\d+)/, "#requestee$1-$2");
            if (target.val() == '?') {
                $(id + '-container').show();
                $(id).focus().select();
            }
            else {
                $(id + '-container').hide();
            }
        });

    // tracking flags
    $('.tracking-flags select')
        .change(function(event) {
            tracking_flag_change(event.target);
        });

    // add attachments
    $('#attachments-add-btn')
        .click(function(event) {
            event.preventDefault();
            window.location.replace('attachment.cgi?bugid=' + BUGZILLA.bug_id + '&action=enter');
        });

    // take button
    $('#take-btn')
        .click(function(event) {
            event.preventDefault();
            $('#field-assigned_to .edit-hide').hide();
            $('#field-assigned_to .edit-show').show();
            $('#assigned_to').val(BUGZILLA.user.login).focus().select();
            $('#top-save-btn').show();
        });

    // reply button
    $('.reply-btn')
        .click(function(event) {
            event.preventDefault();
            var comment_id = $(event.target).data('reply-id');
            var comment_author = $(event.target).data('reply-name');

            var prefix = "(In reply to " + comment_author + " from comment #" + comment_id + ")\n";
            var reply_text = "";
            if (BUGZILLA.user.settings.quote_replies == 'quoted_reply') {
                var text = $('#ct-' + comment_id).text();
                reply_text = prefix + wrapReplyText(text);
            }
            else if (BUGZILLA.user.settings.quote_replies == 'simply_reply') {
                reply_text = prefix;
            }

            // quoting a private comment, check the 'private' cb
            $('#add-comment-private-cb').prop('checked',
                $('#add-comment-private-cb:checked').length || $('#is-private-' + comment_id + ':checked').length);

            // remove embedded links to attachment details
            reply_text = reply_text.replace(/(attachment\s+\d+)(\s+\[[^\[\n]+\])+/gi, '$1');

            if ($('#comment').val() != reply_text) {
                $('#comment').val($('#comment').val() + reply_text);
            }
            scroll_to($('#comment'), function() { $('#comment').focus(); });
        });

    // add comment --> enlarge on focus
    if (BUGZILLA.user.settings.zoom_textareas) {
        $('#comment')
            .focus(function(event) {
                $(event.target).attr('rows', 25);
            });
    }

    // add comment --> private
    $('#add-comment-private-cb')
        .click(function(event) {
            if ($(event.target).prop('checked')) {
                $('#comment').addClass('private-comment');
            }
            else {
                $('#comment').removeClass('private-comment');
            }
        });

    // show "save changes" button if there are any immediately editable elements
    if ($('.module select:visible').length || $('.module input:visible').length) {
        $('#top-save-btn').show();
    }

    // status/resolve as buttons
    $('.resolution-btn')
        .click(function(event) {
            event.preventDefault();
            $('#field-status-view').hide();
            $('#field-status-edit .edit-hide').hide();
            $('#field-status-edit .edit-show').show();
            $('#field-status-edit').show();
            $('#bug_status').val('RESOLVED').change();
            $('#resolution').val($(event.target).text()).change();
            $('#top-save-btn').show();
            if ($(event.target).text() == "DUPLICATE") {
                scroll_to($('body'));
            }
            else {
                scroll_to($('body'), function() { $('#resolution').focus(); });
            }
        });
    $('.status-btn')
        .click(function(event) {
            event.preventDefault();
            $('#field-status-view').hide();
            $('#field-status-edit .edit-hide').hide();
            $('#field-status-edit .edit-show').show();
            $('#field-status-edit').show();
            $('#bug_status').val($(event.target).data('status')).change();
            $('#top-save-btn').show();
            scroll_to($('body'), function() { $('#bug_status').focus(); });
        });

    // vote button
    // ideally this should function like CC and xhr it, but that would require
    // a rewrite of the voting extension
    $('#vote-btn')
        .click(function(event) {
            event.preventDefault();
            window.location.replace('page.cgi?id=voting/user.html&bug_id=' + BUGZILLA.bug_id + '#vote_' + BUGZILLA.bug_id);
        });

    // user-story
    $('#user-story-edit-btn')
        .click(function(event) {
            event.preventDefault();
            $('#user-story').hide();
            $('#user-story-edit-btn').hide();
            $('#cf_user_story').show().focus().select();
            $('#top-save-btn').show();
        });
    $('#user-story-reply-btn')
        .click(function(event) {
            event.preventDefault();
            var text = "(Commenting on User Story)\n" + wrapReplyText($('#cf_user_story').val());
            var current = $('#comment').val();
            if (current != text) {
                $('#comment').val(current + text);
                $('#comment').focus();
                scroll_to($('#bottom-save-btn'));
            }
        });

    // custom textarea fields
    $('.edit-textarea-btn')
        .click(function(event) {
            event.preventDefault();
            var id = $(event.target).attr('id').replace(/-edit$/, '');
            $(event.target).hide();
            $('#' + id + '-view').hide();
            $('#' + id).show().focus().select();
        });

    // date/datetime pickers
    $('.cf_datetime').datetimepicker({
        format: 'Y-m-d G:i:s',
        datepicker: true,
        timepicker: true,
        scrollInput: false,
        lazyInit: false, // there's a bug which prevents img->show from working with lazy:true
        closeOnDateSelect: true
    });
    $('.cf_date').datetimepicker({
        format: 'Y-m-d',
        datepicker: true,
        timepicker: false,
        scrollInput: false,
        lazyInit: false,
        closeOnDateSelect: true
    });
    $('.cf_datetime-img, .cf_date-img')
        .click(function(event) {
            var id = $(event.target).attr('id').replace(/-img$/, '');
            $('#' + id).datetimepicker('show');
        });

    // new bug button
    $.contextMenu({
        selector: '#new-bug-btn',
        trigger: 'left',
        items: [
            {
                name: 'Create a new Bug',
                callback: function() {
                    window.open('enter_bug.cgi', '_blank');
                }
            },
            {
                name: '&hellip; in this product',
                callback: function() {
                    window.open('enter_bug.cgi?product=' + encodeURIComponent($('#product').val()), '_blank');
                }
            },
            {
                name: '&hellip; in this component',
                callback: function() {
                    window.open('enter_bug.cgi?' +
                                'product=' + encodeURIComponent($('#product').val()) +
                                '&component=' + encodeURIComponent($('#component').val()), '_blank');
                }
            },
            {
                name: '&hellip; that blocks this bug',
                callback: function() {
                    window.open('enter_bug.cgi?format=__default__' +
                                '&product=' + encodeURIComponent($('#product').val()) +
                                '&blocked=' + BUGZILLA.bug_id, '_blank');
                }
            },
            {
                name: '&hellip; that depends on this bug',
                callback: function() {
                    window.open('enter_bug.cgi?format=__default__' +
                                '&product=' + encodeURIComponent($('#product').val()) +
                                '&dependson=' + BUGZILLA.bug_id, '_blank');
                }
            },
            {
                name: '&hellip; as a clone of this bug',
                callback: function() {
                    window.open('enter_bug.cgi?format=__default__' +
                                '&product=' + encodeURIComponent($('#product').val()) +
                                '&cloned_bug_id=' + BUGZILLA.bug_id, '_blank');
                }
            },
            {
                name: '&hellip; as a clone, in a different product',
                callback: function() {
                    window.open('enter_bug.cgi?format=__default__' +
                                '&cloned_bug_id=' + BUGZILLA.bug_id, '_blank');
                }
            },
        ]
    });

});

function confirmUnsafeURL(url) {
    return confirm(
        'This is considered an unsafe URL and could possibly be harmful.\n' +
        'The full URL is:\n\n' + url + '\n\nContinue?');
}

// fix url after bug creation/update
if (history && history.replaceState) {
    var href = document.location.href;
    if (!href.match(/show_bug\.cgi/)) {
        history.replaceState(null, BUGZILLA.bug_title, 'show_bug.cgi?id=' + BUGZILLA.bug_id);
        document.title = BUGZILLA.bug_title;
    }
    if (href.match(/show_bug\.cgi\?.*list_id=/)) {
        href = href.replace(/[\?&]+list_id=(\d+|cookie)/, '');
        history.replaceState(null, BUGZILLA.bug_title, href);
    }
}

// ajax wrapper, to simplify error handling and auth
function bugzilla_ajax(request, done_fn, error_fn) {
    $('#xhr-error').hide('');
    $('#xhr-error').html('');
    request.url += (request.url.match('\\?') ? '&' : '?') +
        'Bugzilla_api_token=' + encodeURIComponent(BUGZILLA.api_token);
    if (request.type != 'GET') {
        request.contentType = 'application/json';
    }
    $.ajax(request)
        .done(function(data) {
            if (data.error) {
                $('#xhr-error').html(data.message);
                $('#xhr-error').show('fast');
                if (error_fn)
                    error_fn(data.message);
            }
            else if (done_fn) {
                done_fn(data);
            }
        })
        .error(function(data) {
            $('#xhr-error').html(data.responseJSON.message);
            $('#xhr-error').show('fast');
            if (error_fn)
                error_fn(data.responseJSON.message);
        });
}

// no-ops
function initHidingOptionsForIE() {}
function showFieldWhen() {}
