/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

// expand/collapse module
function slide_module(module, action, fast) {
    if (!module.attr('id'))
        return;
    var latch = module.find('.module-latch');
    var spinner = module.find('.module-spinner');
    var content = $(module.children('.module-content')[0]);
    var duration = fast ? 0 : 200;

    function slide_done() {
        var is_visible = content.is(':visible');
        spinner.attr({
            'aria-expanded': is_visible,
            'aria-label': is_visible ? latch.data('label-expanded') : latch.data('label-collapsed'),
        });
        if (BUGZILLA.user.settings.remember_collapsed)
            localStorage.setItem(module.attr('id') + '.visibility', is_visible ? 'show' : 'hide');
    }

    if (action == 'show') {
        content.slideDown(duration, 'swing', slide_done);
    }
    else if (action == 'hide') {
        content.slideUp(duration, 'swing', slide_done);
    }
    else {
        content.slideToggle(duration, 'swing', slide_done);
    }
}

function init_module_visibility() {
    if (!BUGZILLA.user.settings.remember_collapsed)
        return;
    $('.module').each(function() {
        var that = $(this);
        var id = that.attr('id');
        if (!id) return;
        if (that.data('non-stick')) return;
        var stored = localStorage.getItem(id + '.visibility');
        if (stored) {
            slide_module(that, stored, true);
        }
    });
}

$(function() {
    'use strict';

    // update relative dates
    var relative_timer_duration = 60000;
    var relative_timer_id = window.setInterval(relativeTimer, relative_timer_duration);
    $(document).on('show.visibility', function() {
        relative_timer_id = window.setInterval(relativeTimer, relative_timer_duration);
    });
    $(document).on('hide.visibility', function() {
        window.clearInterval(relative_timer_id);
    });

    function relativeTimer() {
        var now = Math.floor(new Date().getTime() / 1000);
        $('.rel-time').each(function() {
            $(this).text(timeAgo(now - $(this).data('time')));
        });
        $('.rel-time-title').each(function() {
            $(this).attr('title', timeAgo(now - $(this).data('time')));
        });
    }

    // all keywords for autocompletion (lazy-loaded on edit)
    var keywords = [];

    // products with descriptions (also lazy-loaded)
    var products = [];

    // restore edit mode after navigating back
    function restoreEditMode() {
        if (!$('#editing').val())
            return;
        $('.module')
            .each(function() {
                slide_module($(this), 'hide', true);
            });
        $($('#editing').val().split(' '))
            .each(function() {
                slide_module($('#' + this), 'show', true);
            });
        $('#mode-btn').click();
        $('.save-btn').prop('disabled', false);
        $('#editing').val('');
    }

    // expand/colapse module
    $('.module-latch')
        .click(function(event) {
            event.preventDefault();
            slide_module($(this).parents('.module'));
        })
        .keydown(function(event) {
            // expand/colapse module with the enter or space key
            if (event.keyCode === 13 || event.keyCode === 32) {
                event.preventDefault();
                slide_module($(this).parents('.module'));
            }
        });

    // toggle obsolete attachments
    $('#attachments-obsolete-btn')
        .click(function(event) {
            event.preventDefault();
            $(event.target).text(($('#attachments tr:hidden').length ? 'Hide' : 'Show') + ' Obsolete Attachments');
            $('#attachments tr.attach-obsolete').toggle();
        });

    // url --> unsafe warning
    $('.bug-url')
        .click(function(event) {
            var that = $(this);
            event.stopPropagation();
            if (!that.data('safe')) {
                event.preventDefault();
                if (confirm('This is considered an unsafe URL and could possibly be harmful. ' +
                            'The full URL is:\n\n' + that.attr('href') + '\n\nContinue?'))
                {
                    try {
                        window.open(that.attr('href'));
                    } catch(ex) {
                        alert('Malformed URL');
                    }
                }
            }
        });

    // top btn
    $('#top-btn')
        .click(function(event) {
            event.preventDefault();
            $.scrollTo($('body'));
        });

    // bottom btn
    $('#bottom-btn')
        .click(function(event) {
            event.preventDefault();
            $.scrollTo($('#bottom-actions'));
        });

    // hide floating message when clicked
    $('#floating-message')
        .click(function(event) {
            event.preventDefault();
            $(this).hide();
        });

    // use non-native tooltips for relative/absolute times and bug summaries
    $('.rel-time, .rel-time-title, .abs-time-title, .bz_bug_link, .tt').tooltip({
        position: { my: "left top+8", at: "left bottom", collision: "flipfit" },
        show: { effect: 'none' },
        hide: { effect: 'none' }
    });

    // tooltips create a new ui-helper-hidden-accessible div each time a
    // tooltip is shown.  this is never removed leading to memory leak and
    // bloated dom.  http://bugs.jqueryui.com/ticket/10689
    $('.ui-helper-hidden-accessible').remove();

    // product/component info
    $('.spin-toggle, #product-latch, #component-latch')
        .click(function(event) {
            spin_toggle(event);
        }).keydown(function(event) {
            // allow space or enter to toggle visibility
            if (event.keyCode == 13 || event.keyCode == 32) {
                spin_toggle(event);
            }
        });

    function spin_toggle(event) {
        event.preventDefault();
        var type  = $(event.target).data('for');
        var latch = $('#' + type + '-latch');
        var name  = $('#' + type + '-name');
        var info  = $('#' + type + '-info');
        var label = latch.attr('aria-label');

        if (latch.data('expanded')) {
            label = label.replace(/^hide/, 'show');
            latch.data('expanded', false).html('&#9656;');
            latch.attr('aria-expanded', false);
            info.hide();
        }
        else {
            label = label.replace(/^show/, 'hide');
            latch.data('expanded', true).html('&#9662;');
            latch.attr('aria-expanded', true);
            info.show();
        }
        latch.attr('aria-label', label);
        name.attr('title', label);
    }

    // cc list

    function ccListLoading() {
        $('#cc-list').html(
            '<img src="extensions/BugModal/web/throbber.gif" width="16" height="11"> Loading...'
        );
    }

    function ccListUpdate() {
        bugzilla_ajax(
            {
                url: 'rest/bug_modal/cc/' + BUGZILLA.bug_id
            },
            function(data) {
                $('#cc-list').html(data.html);
                $('#cc-latch').data('fetched', true);
                $('#cc-list .cc-user').hover(
                    function() {
                        $('#ccr-' + $(this).data('n')).css('visibility', 'visible');
                    },
                    function() {
                        $('#ccr-' + $(this).data('n')).css('visibility', 'hidden');
                    }
                );
                $('#cc-list .cc-remove')
                    .click(function(event) {
                        event.preventDefault();
                        $('#top-save-btn').show();
                        var n = $(this).data('n');
                        var ccu = $('#ccu-' + n);
                        if (ccu.hasClass('cc-removed')) {
                            ccu.removeClass('cc-removed');
                            $('#cc-' + n).remove();
                        }
                        else {
                            $('#removecc').val('on');
                            ccu.addClass('cc-removed');
                            $('<input>').attr({
                                type: 'hidden',
                                id: 'cc-' + n,
                                value: $('#ccr-' + n).data('login'),
                                name: 'cc'
                            }).appendTo('#changeform');
                        }
                    });
            }
        );
    }

    if (BUGZILLA.user.id) {
        $('#cc-summary').addClass('cc-loadable');
        $('#cc-latch, #cc-summary')
            .click(function(event) {
                cc_toggle(event);
            }).keydown(function(event) {
                // allow space or enter to toggle visibility
                if (event.keyCode == 13 || event.keyCode == 32) {
                    cc_toggle(event);
                }
            });
    }

    function cc_toggle(event) {
        event.preventDefault();
        var latch = $('#cc-latch');
        var label = latch.attr('aria-label');
        if (latch.data('expanded')) {
            label = label.replace(/^hide/, 'show');
            latch.data('expanded', false).html('&#9656;');
            $('#cc-list').hide();
        }
        else {
            latch.data('expanded', true).html('&#9662;');
            label = label.replace(/^show/, 'hide');
            $('#cc-list').show();
            if (!latch.data('fetched')) {
                ccListLoading();
                ccListUpdate();
            }
        }
        latch.attr('aria-label', label);
        $('#cc-summary').attr('aria-label', label);
    }

    // copy summary to clipboard

    function clipboardSummary() {
        return 'Bug ' + BUGZILLA.bug_id + ' - ' + $('#field-value-short_desc').text();
    }

    if ($('#copy-summary').length) {
        var hasExecCopy = false;
        try {
            hasExecCopy = document.queryCommandSupported("copy");
        } catch(ex) {
            // ignore
        }

        if (hasExecCopy) {
            $('#copy-summary')
                .click(function() {
                    // execCommand("copy") only works on selected text
                    $('#clip-container').show();
                    $('#clip').val(clipboardSummary()).select();
                    document.execCommand("copy");
                    $('#clip-container').hide();
                });
        }
        else {
            // we don't know if flash is enabled without waiting for load to timeout
            // remember the flash enabled state between pages
            var hasFlash = true;
            if (localStorage.getItem('hasFlash') === null) {
                $('#copy-summary').hide();
            }
            else {
                hasFlash = localStorage.getItem('hasFlash');
            }
            if (hasFlash) {
                ZeroClipboard.config({ flashLoadTimeout: 5000 });
                var zero = new ZeroClipboard($('#copy-summary'));
                zero.on({
                    'ready': function(event) {
                        $('#copy-summary').show();
                        localStorage.setItem('hasFlash', true);
                    },
                    'error': function(event) {
                        console.log(event.message);
                        zero.destroy();
                        $('#global-zeroclipboard-html-bridge').remove();
                        $('#copy-summary').hide();
                        localStorage.removeItem('hasFlash');
                    },
                    'copy': function(event) {
                        var clipboard = event.clipboardData;
                        clipboard.setData('text/plain', clipboardSummary());
                    }
                });
            }
        }
    }

    // lightboxes
    $('.lightbox, .comment-text .lightbox + span:first-of-type a:first-of-type')
        .click(function(event) {
            if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey)
                return;
            event.preventDefault();
            lb_show(this);
        });

    // when copying the bug id and summary, reformat to remove \n and alias
    $(document).on(
        'copy', function(event) {
            var selection = document.getSelection().toString().trim();
            var match = selection.match(/^(Bug \d+)\s*\n(.+)$/) ||
                selection.match(/^(Bug \d+)\s+\([^\)]+\)\s*\n(.+)$/);
            if (match) {
                var content = match[1] + ' - ' + match[2].trim();
                if (event.originalEvent.clipboardData) {
                    event.originalEvent.clipboardData.setData('text/plain', content);
                }
                else if (window.clipboardData) {
                    window.clipboardData.setData('Text', content);
                }
                else {
                    return;
                }
                event.preventDefault();
            }
        });

    // action button actions

    // reset
    $('#action-reset')
        .click(function(event) {
            event.preventDefault();
            var visible = $(this).data('modules');
            $('.module-content').each(function() {
                var content = $(this);
                var moduleID = content.parent('.module').attr('id');
                var isDefault = $.inArray(moduleID, visible) !== -1;
                if (content.is(':visible') && !isDefault) {
                    slide_module($('#' + moduleID), 'hide');
                }
                else if (content.is(':hidden') && isDefault) {
                    slide_module($('#' + moduleID), 'show');
                }
            });
        })
        .data('modules', $('.module-content:visible').map(function() {
            return $(this).parent('.module').attr('id');
        }));

    // expand all modules
    $('#action-expand-all')
        .click(function(event) {
            event.preventDefault();
            $('.module-content:hidden').each(function() {
                slide_module($(this).parent('.module'));
            });
        });

    // collapse all modules
    $('#action-collapse-all')
        .click(function(event) {
            event.preventDefault();
            $('.module-content:visible').each(function() {
                slide_module($(this).parent('.module'));
            });
        });

    // add comment menuitem, scroll the textarea into view
    $('#action-add-comment, #add-comment-btn')
        .click(function(event) {
            event.preventDefault();
            // focus first to grow the textarea, so we scroll to the correct location
            $('#comment').focus();
            $.scrollTo($('#bottom-save-btn'));
        });

    // last comment menuitem
    $('#action-last-comment')
        .click(function(event) {
            event.preventDefault();
            var id = $('.comment:last')[0].parentNode.id;
            $.scrollTo(id);
        });

    // show bug history
    $('#action-history')
        .click(function(event) {
            event.preventDefault();
            document.location.href = 'show_activity.cgi?id=' + BUGZILLA.bug_id;
        });

    // use scrollTo for in-page activity links
    $('.activity-ref')
        .click(function(event) {
            event.preventDefault();
            $.scrollTo($(this).attr('href').substr(1));
        });

    // Update readable bug status
    var rbs = $("#readable-bug-status");
    var rbs_text = bugzillaReadableStatus.readable(rbs.data('readable-bug-status'));
    rbs.text(rbs_text);
    
    if (BUGZILLA.user.id === 0) return;

    //
    // anything after this point is only executed for logged in users
    //

    // dirty field tracking
    $('#changeform select').each(function() {
        var that = $(this);
        var dirty = $('#' + that.attr('id') + '-dirty');
        if (!dirty) return;
        var isMultiple = that.attr('multiple');

        // store the option that had the selected attribute when we
        // initially loaded
        var value = that.find('option[selected]').map(function() { return this.value; }).toArray();
        if (value.length === 0 && !that.attr('multiple'))
            value = that.find('option:first').map(function() { return this.value; }).toArray();
        that.data('preselected', value);

        // if the user hasn't touched a field, override the browser's choice
        // with bugzilla's
        if (!dirty.val())
            that.val(value);
    });

    // edit/save mode button
    $('#mode-btn')
        .click(function(event) {
            event.preventDefault();

            // hide buttons, old error messages
            $('#mode-btn-readonly').hide();

            // toggle visibility
            $('.edit-hide').hide();
            $('.edit-show').show();

            // expand specific modules during the initial edit
            if (!$('#editing').val())
                slide_module($('#module-details'), 'show');

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
                    keywords = data.keywords;
                    $('#keywords')
                        .devbridgeAutocomplete({
                            lookup: function(query, done) {
                                query = query.toLowerCase();
                                var matchStart =
                                    $.grep(keywords, function(keyword) {
                                        return keyword.toLowerCase().substr(0, query.length) === query;
                                    });
                                var matchSub =
                                    $.grep(keywords, function(keyword) {
                                        return keyword.toLowerCase().indexOf(query) !== -1 &&
                                            $.inArray(keyword, matchStart) === -1;
                                    });
                                var suggestions =
                                    $.map($.merge(matchStart, matchSub), function(suggestion) {
                                        return { value: suggestion };
                                    });
                                done({ suggestions: suggestions });
                            },
                            tabDisabled: true,
                            delimiter: /,\s*/,
                            minChars: 0,
                            autoSelectFirst: false,
                            triggerSelectOnValidInput: false,
                            formatResult: function(suggestion, currentValue) {
                                // disable <b> wrapping of matched substring
                                return suggestion.value.htmlEncode();
                            },
                            onSearchStart: function(params) {
                                var that = $(this);
                                // adding spaces shouldn't initiate a new search
                                var parts = that.val().split(/,\s*/);
                                var query = parts[parts.length - 1];
                                return query === $.trim(query);
                            },
                            onSelect: function() {
                                this.value = this.value + ', ';
                                this.focus();
                            }
                        })
                        .addClass('bz_autocomplete');

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

    // disable the save buttons while posting
    $('.save-btn')
        .click(function(event) {
            event.preventDefault();
            if (document.changeform.checkValidity && !document.changeform.checkValidity())
                return;
            $('.save-btn').attr('disabled', true);
            this.form.submit();

            // remember expanded modules
            $('#editing').val(
                $('.module .module-content:visible')
                    .parent()
                    .map(function(el) { return $(this).attr('id'); })
                    .toArray()
                    .join(' ')
            );
        })
        .attr('disabled', false);

    // cc toggle (follow/stop following)
    $('#cc-btn')
        .click(function(event) {
            event.preventDefault();
            var is_cced = $(event.target).data('is-cced') == '1';

            var cc_change;
            var cc_count = $('#cc-summary').data('count');
            if (is_cced) {
                cc_change = { remove: [ BUGZILLA.user.login ] };
                cc_count--;
                $('#cc-btn')
                    .text('Follow')
                    .data('is-cced', '0')
                    .prop('disabled', true);
            }
            else {
                cc_change = { add: [ BUGZILLA.user.login ] };
                cc_count++;
                $('#cc-btn')
                    .text('Stop Following')
                    .data('is-cced', '1')
                    .prop('disabled', true);
            }
            is_cced = !is_cced;

            // update visible count
            $('#cc-summary').data('count', cc_count);
            if (cc_count == 1) {
                $('#cc-summary').text(is_cced ? 'Just you' : '1 person');
            }
            else {
                $('#cc-summary').text(cc_count + ' people');
            }

            // clear/update user list
            $('#cc-latch').data('fetched', false);
            if ($('#cc-latch').data('expanded'))
                ccListLoading();

            // show message
            $('#floating-message-text')
                .text(is_cced ? 'You are now following this bug' : 'You are no longer following this bug');
            $('#floating-message')
                .fadeIn(250)
                .delay(2500)
                .fadeOut();

            // show/hide "add me to the cc list"
            if (is_cced) {
                $('#add-self-cc-container').hide();
                $('#add-self-cc').attr('disabled', true);
            }
            else {
                $('#add-self-cc-container').show();
                $('#add-self-cc').attr('disabled', false);
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
                            .text('Stop Following')
                            .data('is-cced', '1');
                    }
                    else if (data.bugs[0].changes.cc.removed == BUGZILLA.user.login) {
                        $('#cc-btn')
                            .text('Follow')
                            .data('is-cced', '0');
                    }
                    if ($('#cc-latch').data('expanded'))
                        ccListUpdate();
                },
                function(message) {
                    $('#cc-btn').prop('disabled', false);
                    if ($('#cc-latch').data('expanded'))
                        ccListUpdate();
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
            window.location.replace($('#this-bug').attr('href'));
        });

    // Open help page
    $('#help-btn')
        .click(function(event) {
            event.preventDefault();
            window.open("https://wiki.mozilla.org/BMO/UserGuide", "_blank");
        });

    // needinfo in people section -> scroll to near-comment ui
    $('#needinfo-scroll')
        .click(function(event) {
            event.preventDefault();
            $.scrollTo($('#needinfo_role'), function() { $('#needinfo_role').focus(); });
        });

    // knob
    $('#bug_status, #bottom-bug_status')
        .change(function(event) {
            var that = $(this);
            var val = that.val();
            var other = $(that.attr('id') == 'bug_status' ? '#bottom-bug_status' : '#bug_status');
            other.val(val);
            if (val == "RESOLVED" || val == "VERIFIED") {
                $('#resolution, #bottom-resolution').change().show();
            }
            else {
                $('#resolution, #bottom-resolution').hide();
                $('#duplicate-container, #bottom-duplicate-container').hide();
                $('#mark-as-dup-btn, #bottom-mark-as-dup-btn').show();
            }
        })
        .change();
    $('#resolution, #bottom-resolution')
        .change(function(event) {
            var that = $(this);
            var val = that.val();
            var other = $(that.attr('id') == 'resolution' ? '#bottom-resolution' : '#resolution');
            other.val(val);
            var bug_status = $('#bug_status').val();
            if ((bug_status == "RESOLVED" || bug_status == "VERIFIED") && val == "DUPLICATE") {
                $('#duplicate-container, #bottom-duplicate-container').show();
                $('#mark-as-dup-btn, #bottom-mark-as-dup-btn').hide();
                $(that.attr('id') == 'resolution' ? '#dup_id' : '#bottom-dup_id').focus();
            }
            else {
                $('#duplicate-container, #bottom-duplicate-container').hide();
                $('#mark-as-dup-btn, #bottom-mark-as-dup-btn').show();
            }
        })
        .change();
    $('#mark-as-dup-btn, #bottom-mark-as-dup-btn')
        .click(function(event) {
            event.preventDefault();
            $('#bug_status').val('RESOLVED').change();
            $('#resolution').val('DUPLICATE').change();
            $($(this).attr('id') == 'mark-as-dup-btn' ? '#dup_id' : '#bottom-dup_id').focus();
        });
    $('#dup_id, #bottom-dup_id')
        .change(function(event) {
            var that = $(this);
            var other = $(that.attr('id') == 'dup_id' ? '#bottom-dup_id' : '#dup_id');
            other.val(that.val());
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

    // take button
    $('.take-btn')
        .click(function(event) {
            event.preventDefault();
            $('#field-status-view').hide();
            $('#field-status-edit').show();
            if ($('#bug_status option').filter(function() { return $(this).val() == 'ASSIGNED'; }).length) {
                $('#assigned-container').show();
            }
            var field = $(this).data('field');
            $('#field-' + field + '.edit-hide').hide();
            $('#field-' + field + '.edit-show').show();
            $('#' + field).val(BUGZILLA.user.login).focus().select();
            $('#top-save-btn').show();
            if ($('#set-default-assignee').is(':checked')) {
                $('#set-default-assignee').click();
            }
        });

    // mark as assigned
    $('#mark-as-assigned-btn')
        .click(function(event) {
            event.preventDefault();
            $('#bug_status').val('ASSIGNED').change();
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
            $.scrollTo($('#comment'), function() { $('#comment').focus(); });
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
            $('#field-status-edit').show();
            $('#field-status-edit .name').show();
            $('#bug_status').val('RESOLVED').change();
            $('#bottom-resolution').val($(event.target).text()).change();
            $('#top-save-btn').show();
            $('#resolve-as').hide();
            $('#bottom-status').show();
            $('#bottom-dup_id').focus();
        });
    $('.status-btn')
        .click(function(event) {
            event.preventDefault();
            $('#field-status-view').hide();
            $('#field-status-edit').show();
            $('#bug_status').val($(event.target).data('status')).change();
            $('#top-save-btn').show();
            $('#resolve-as').hide();
            $('#bottom-status').show();
        });

    // vote button
    // ideally this should function like CC and xhr it, but that would require
    // a rewrite of the voting extension
    $('#vote-btn')
        .click(function(event) {
            event.preventDefault();
            window.location.href = 'page.cgi?id=voting/user.html&bug_id=' + BUGZILLA.bug_id + '#vote_' + BUGZILLA.bug_id;
        });

    // user-story
    $('#user-story-edit-btn')
        .click(function(event) {
            event.preventDefault();
            $('#user-story').hide();
            $('#user-story-edit-btn').hide();
            $('#top-save-btn').show();
            $('#cf_user_story').show();
            // don't focus the user-story field when restoring edit mode after navigation
            if ($('#editing').val() === '')
                $('#cf_user_story').focus().select();
        });
    $('#user-story-reply-btn')
        .click(function(event) {
            event.preventDefault();
            var text = "(Commenting on User Story)\n" + wrapReplyText($('#cf_user_story').val());
            var current = $('#comment').val();
            if (current != text) {
                $('#comment').val(current + text);
                $('#comment').focus();
                $.scrollTo($('#bottom-save-btn'));
            }
        });

    // cab review 'gate'
    $('#cab-review-gate-close')
        .click(function(event) {
            event.preventDefault();
            $('#cab-review-gate').hide();
            $('#cab-review-edit').show();
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

    // timetracking
    $('#work_time').change(function() {
        // subtracts time spent from remaining time
        // prevent negative values if work_time > fRemainingTime
        var new_time = Math.max(BUGZILLA.remaining_time - $('#work_time').val(), 0.0);
        // get upto 2 decimal places
        $('#remaining_time').val(Math.round((new_time * 100)/100).toFixed(1));
    });
    $('#remaining_time').change(function() {
        // if the remaining time is changed manually, update BUGZILLA.remaining_time
        BUGZILLA.remaining_time = $('#remaining_time').val();
    });

    // "reset to default" checkboxes
    $('#product, #component')
        .change(function(event) {
            $('.set-default-container').show();
            $('#set-default-assignee').prop('checked', $('#assigned_to').val() == BUGZILLA.default_assignee).change();
            $('#set-default-qa-contact').prop('checked', $('#qa_contact').val() == BUGZILLA.default_qa_contact).change();
            slide_module($('#module-people'), 'show');
        });
    $('.set-default')
        .change(function(event) {
            var cb = $(event.target);
            var input = $('#' + cb.data('for'));
            input.attr('disabled', cb.prop('checked'));
        })
        .change();

    // hotkeys
    $(window)
        .keydown(function(event) {
            if (!(event.ctrlKey || event.metaKey))
                return;
            switch(String.fromCharCode(event.which).toLowerCase()) {
                // ctrl+e or meta+e = enter edit mode
                case 'e':
                    if (event.shiftKey)
                        return;
                    // don't conflict with text input shortcut
                    if (document.activeElement.nodeNode == 'INPUT' || document.activeElement.nodeName == 'TEXTAREA')
                        return;
                    if ($('#cancel-btn:visible').length === 0) {
                        event.preventDefault();
                        $('#mode-btn').click();
                    }
                    break;

                // ctrl+shift+p = toggle comment preview
                case 'p':
                    if (event.metaKey || !event.shiftKey)
                        return;
                    if (document.activeElement.id == 'comment') {
                        event.preventDefault();
                        $('#comment-preview-tab').click();
                    }
                    else if ($('#comment-preview:visible').length !== 0) {
                        event.preventDefault();
                        $('#comment-edit-tab').click();
                    }
                    break;
            }
        });

    // add cc button
    $('#add-cc-btn')
        .click(function(event) {
            event.preventDefault();
            $('#add-cc-btn').hide();
            $('#add-cc-container').show();
            $('#top-save-btn').show();
            $('#add-cc').focus();
        });

    // Add user to cc list if they mark the bug as security sensitive
    $('.restrict_sensitive')
        .change(function(event) {
            $('#add-self-cc:not(:checked)').attr('checked', true);
        });

    // product change --> load components, versions, milestones, groups
    $('#product').data('default', $('#product').val());
    $('#component, #version, #target_milestone').each(function() {
        $(this).data('default', $(this).val());
    });
    $('#product')
        .change(function(event) {
            $('#product-throbber').show();
            $('#component, #version, #target_milestone').attr('disabled', true);

            slide_module($('#module-tracking'), 'show');

            $.each($('input[name=groups]'), function() {
                if (this.checked) {
                    slide_module($('#module-security'), 'show');
                    return false;
                }
            });

            bugzilla_ajax(
                {
                    url: 'rest/bug_modal/new_product/' + BUGZILLA.bug_id + '?product=' + encodeURIComponent($('#product').val())
                },
                function(data) {
                    $('#product-throbber').hide();
                    $('#component, #version, #target_milestone').attr('disabled', false);
                    var is_default = $('#product').val() == $('#product').data('default');

                    // populate selects
                    $.each(data, function(key, value) {
                        if (key == 'groups') return;
                        var el = $('#' + key);
                        if (!el) return;
                        el.empty();
                        var selected = el.data('preselect');
                        $(value).each(function(i, v) {
                            el.append($('<option>', { value: v.name, text: v.name }));
                            if (typeof selected === 'undefined' && v.selected)
                                selected = v.name;
                        });
                        el.val(selected);
                        el.prop('required', true);
                        if (is_default) {
                            el.removeClass('attention');
                            el.val(el.data('default'));
                        }
                        else {
                            el.addClass('attention');
                        }
                    });

                    // update groups
                    var dirtyGroups = [];
                    var any_groups_checked = 0;
                    $('#module-security').find('input[name=groups]').each(function() {
                        var that = $(this);
                        var defaultChecked = !!that.attr('checked');
                        if (defaultChecked !== that.is(':checked')) {
                            dirtyGroups.push({ name: that.val(), value: that.is(':checked') });
                        }
                        if (that.is(':checked')) {
                            any_groups_checked = 1;
                        }
                    });
                    $('#module-security .module-content')
                        .html(data.groups)
                        .addClass('attention');
                    $.each(dirtyGroups, function() {
                        $('#module-security').find('input[value=' + this.name + ']').prop('checked', this.value);
                    });
                    // clear any default groups if user was making bug public
                    // unless the group is mandatory for the new product
                    if (!any_groups_checked) {
                        $('#module-security').find('input[name=groups]').each(function() {
                            var that = $(this);
                            if (!that.data('mandatory')) {
                                that.prop('checked', false);
                            }
                        });
                    }
                },
                function() {
                    $('#product-throbber').hide();
                    $('#component, #version, #target_milestone').attr('disabled', false);
                }
            );
        });

    // product/component search
    $('#product-search')
        .click(function(event) {
            event.preventDefault();
            $('#product').hide();
            $('#product-search').hide();
            $('#product-search-cancel').show();
            $('.pcs-form').show();
            $('#pcs').val('').focus();
        });
    $('#product-search-cancel')
        .click(function(event) {
            event.preventDefault();
            $('#product-search-error').hide();
            $('.pcs-form').hide();
            $('#product').show();
            $('#product-search-cancel').hide();
            $('#product-search').show();
        });
    $('#pcs')
        .devbridgeAutocomplete('setOptions', {
            onSelect: function(suggestion) {
                $('#product-search-error').hide();
                $('.pcs-form').hide();
                $('#product-search-cancel').hide();
                $('#product-search').show();
                if ($('#product').val() != suggestion.data.product) {
                    $('#component').data('preselect', suggestion.data.component);
                    $('#product').val(suggestion.data.product).change();
                }
                else {
                    $('#component').val(suggestion.data.component);
                }
                $('#product').show();
            }
        });
    $(document)
        .on('pcs:search', function(event) {
            $('#product-search-error').hide();
        })
        .on('pcs:results', function(event) {
            $('#product-search-error').hide();
        })
        .on('pcs:no_results', function(event) {
            $('#product-search-error')
                .prop('title', 'No components found')
                .show();
        })
        .on('pcs:too_many_results', function(event, el) {
            $('#product-search-error')
                .prop('title', 'Results limited to ' + el.data('max_results') + ' components')
                .show();
        })
        .on('pcs:error', function(event, message) {
            $('#product-search-error')
                .prop('title', message)
                .show();
        });

    // comment preview
    var last_comment_text = '';
    $('#comment-tabs li').click(function() {
        var that = $(this);
        if (that.attr('aria-selected') === 'true')
            return;

        // ensure preview's height matches the comment
        var comment = $('#comment');
        var preview = $('#comment-preview');
        var comment_height = comment[0].offsetHeight;

        // change tabs
        $('#comment-tabs li').attr({ tabindex: -1, 'aria-selected': false });
        $('.comment-tabpanel').hide();
        that.attr({ tabindex: 0, 'aria-selected': true });
        var tabpanel = $('#' + that.attr('aria-controls')).show();
        var focus = that.data('focus');
        if (focus !== '') {
            $('#' + focus).focus();
        }

        // update preview
        preview.css('height', comment_height + 'px');
        if (tabpanel.attr('id') != 'comment-preview-tabpanel' || last_comment_text == comment.val())
            return;
        $('#preview-throbber').show();
        preview.html('');
        bugzilla_ajax(
            {
                url: 'rest/bug/comment/render',
                type: 'POST',
                data: { text: comment.val() },
                hideError: true
            },
            function(data) {
                $('#preview-throbber').hide();
                preview.html(data.html);
            },
            function(message) {
                $('#preview-throbber').hide();
                var container = $('<div/>');
                container.addClass('preview-error');
                container.text(message);
                preview.html(container);
            }
        );
        last_comment_text = comment.val();
    }).keydown(function(event) {
        var that = $(this);
        var tabs = $('#comment-tabs li');
        var target;

        // enable keyboard navigation on tabs
        switch (event.keyCode) {
            case 35: // End
                target = tabs.last();
                break;
            case 36: // Home
                target = tabs.first();
                break;
            case 37: // Left arrow
                target = that.prev('[role="tab"]');
                break;
            case 39: // Right arrow
                target = that.next('[role="tab"]');
                break;
        }

        if (target && target.length) {
            event.preventDefault();
            target.click().focus();
        }
    });

    // dirty field tracking
    $('#changeform select')
        .change(function() {
            var that = $(this);
            var dirty = $('#' + that.attr('id') + '-dirty');
            if (!dirty) return;
            if (that.attr('multiple')) {
                var preselected = that.data('preselected');
                var selected = that.val();
                var isDirty = preselected.length != selected.length;
                if (!isDirty) {
                    for (var i = 0, l = preselected.length; i < l; i++) {
                        if (selected[i] != preselected[i]) {
                            isDirty = true;
                            break;
                        }
                    }
                }
                dirty.val(isDirty ? '1' : '');
            }
            else {
                dirty.val(that.val() === that.data('preselected')[0] ? '' : '1');
            }
        });

    // finally switch to edit mode if we navigate back to a page that was editing
    $(window).on('pageshow', restoreEditMode);
    restoreEditMode();
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
        request.processData = false;
        if (request.data && request.data.constructor === Object) {
            request.data = JSON.stringify(request.data);
        }
    }
    return $.ajax(request)
        .done(function(data) {
            if (data.error) {
                if (!request.hideError) {
                    $('#xhr-error').html(data.message);
                    $('#xhr-error').show('fast');
                }
                if (error_fn)
                    error_fn(data.message);
            }
            else if (done_fn) {
                done_fn(data);
            }
        })
        .fail(function(data) {
            if (data.statusText === 'abort')
                return;
            var message = data.responseJSON ? data.responseJSON.message : 'Unexpected Error'; // all errors are unexpected :)
            if (!request.hideError) {
                $('#xhr-error').html(message);
                $('#xhr-error').show('fast');
            }
            if (error_fn)
                error_fn(message);
        });
}

// lightbox

function lb_show(el) {
    $(window).trigger('close');
    $(document).bind('keyup.lb', function(event) {
        if (event.keyCode == 27) {
            lb_close(event);
        }
    });
    var overlay = $('<div>')
        .prop('id', 'lb_overlay')
        .css({ opacity: 0 })
        .appendTo('body');
    var overlay2 = $('<div>')
        .prop('id', 'lb_overlay2')
        .css({ top: $(window).scrollTop() + 5 })
        .appendTo('body');
    var title = $('<div>')
        .prop('id', 'lb_text')
        .appendTo(overlay2);
    var img = $('<img>')
        .prop('id', 'lb_img')
        .prop('src', el.href)
        .prop('alt', 'Loading...')
        .css({ opacity: 0 })
        .appendTo(overlay2)
        .click(function(event) {
            event.stopPropagation();
            window.location.href = el.href;
        });
    var close_btn = $('<button>')
        .prop('id', 'lb_close_btn')
        .prop('type', 'button')
        .addClass('minor')
        .text('Close')
        .appendTo(overlay2);
    title.text(el.title);
    overlay.add(overlay2).click(lb_close);
    img.add(overlay).animate({ opacity: 1 }, 200);
}

function lb_close(event) {
    event.preventDefault();
    $(document).unbind('keyup.lb');
    $('#lb_overlay, #lb_overlay2, #lb_close_btn, #lb_img, #lb_text').remove();
}

$(function() {
    $("button.button-link").on("click", function (event) {
        event.preventDefault();
        window.location = $(this).data("href");
    });
});

// extensions

(function($) {
    $.extend({
        // Case insensative $.inArray (http://api.jquery.com/jquery.inarray/)
        // $.inArrayIn(value, array [, fromIndex])
        //  value (type: String)
        //    The value to search for
        //  array (type: Array)
        //    An array through which to search.
        //  fromIndex (type: Number)
        //    The index of the array at which to begin the search.
        //    The default is 0, which will search the whole array.
        inArrayIn: function(elem, arr, i) {
            // not looking for a string anyways, use default method
            if (typeof elem !== 'string') {
                return $.inArray.apply(this, arguments);
            }
            // confirm array is populated
            if (arr) {
                var len = arr.length;
                i = i ? (i < 0 ? Math.max(0, len + i) : i) : 0;
                elem = elem.toLowerCase();
                for (; i < len; i++) {
                    if (i in arr && arr[i].toLowerCase() == elem) {
                        return i;
                    }
                }
            }
            // stick with inArray/indexOf and return -1 on no match
            return -1;
        },

        // Bring an element into view, leaving space for the outline.
        // If passed a string, it will be treated as an id - the page will scroll
        // unanimated and the url will be added to the browser's history.
        // If passed an element, an smooth scroll will take place and no entry
        // will be added to the history.
        scrollTo: function(target, complete) {
            if (typeof target === 'string') {
                var el = $('#' + target);
                window.location.hash = target;
                var $html = $('html');
                if (Math.abs($html.scrollTop() - el.offset().top) <= 1) {
                    $html.scrollTop($html.scrollTop() - 10);
                }
                $html.scrollLeft(0);
            }
            else {
                var offset = target.offset();
                $('html')
                    .animate({
                            scrollTop: offset.top - 20,
                            scrollLeft: 0
                        },
                        200,
                        complete
                    );
            }
        }

    });
})(jQuery);
