/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    'use strict';

    // comment collapse/expand

    function toggleChange(spinner, forced) {
        var spinnerID = spinner.attr('id');
        var id = spinnerID.substring(spinnerID.indexOf('-') + 1);

        var activitySelector = $('#view-toggle-cc').data('shown') === '1' ? '.activity' : '.activity:not(.cc-only)';

        // non-comment toggle
        if (spinnerID.substr(0, 1) == 'a') {
            var changeSet = spinner.parents('.change-set');
            if (forced == 'hide') {
                changeSet.find(activitySelector).hide();
                changeSet.find('.gravatar').css('width', '16px').css('height', '16px');
                $('#ar-' + id).hide();
                spinner.text('+');
            }
            else if (forced == 'show' || forced == 'reset') {
                changeSet.find(activitySelector).show();
                changeSet.find('.gravatar').css('width', '32px').css('height', '32px');
                $('#ar-' + id).show();
                spinner.text('-');
            }
            else {
                changeSet.find(activitySelector).slideToggle('fast', function() {
                    $('#ar-' + id).toggle();
                    if (changeSet.find(activitySelector + ':visible').length) {
                        changeSet.find('.gravatar').css('width', '32px').css('height', '32px');
                        spinner.text('-');
                    }
                    else {
                        changeSet.find('.gravatar').css('width', '16px').css('height', '16px');
                        spinner.text('+');
                    }
                });
            }
            return;
        }

        // find the "real spinner", which is the one on the non-default-collapsed block
        var realSpinner = $('#cs-' + id);
        var defaultCollapsed = realSpinner.data('ch');
        if (defaultCollapsed === undefined) {
            defaultCollapsed = spinner.attr('id').substring(0, 4) === 'ccs-';
            realSpinner.data('ch', defaultCollapsed);
        }
        if (forced === 'reset') {
            forced = defaultCollapsed ? 'hide' : 'show';
        }

        // comment toggle
        if (forced === 'hide') {
            if (defaultCollapsed) {
                $('#ch-' + id).hide();
                $('#cc-' + id).show();
            }
            $('#ct-' + id).hide();
            if (BUGZILLA.user.id !== 0)
                $('#ctag-' + id).hide();
            $('#c' + id).find(activitySelector).hide();
            $('#c' + id).find('.comment-tags').hide();
            $('#c' + id).find('.comment-tags').hide();
            $('#c' + id).find('.gravatar').css('width', '16px').css('height', '16px');
            $('#cr-' + id).hide();
            realSpinner.text('+');
        }
        else if (forced == 'show') {
            if (defaultCollapsed) {
                $('#cc-' + id).hide();
                $('#ch-' + id).show();
            }
            $('#ct-' + id).show();
            if (BUGZILLA.user.id !== 0)
                $('#ctag-' + id).show();
            $('#c' + id).find(activitySelector).show();
            $('#c' + id).find('.comment-tags').show();
            $('#c' + id).find('.comment-tags').show();
            $('#c' + id).find('.gravatar').css('width', '32px').css('height', '32px');
            $('#cr-' + id).show();
            realSpinner.text('-');
        }
        else {
            $('#ct-' + id).slideToggle('fast', function() {
                $('#c' + id).find(activitySelector).toggle();
                if ($('#ct-' + id + ':visible').length) {
                    $('#c' + id).find('.comment-tags').show();
                    realSpinner.text('-');
                    $('#cr-' + id).show();
                    if (BUGZILLA.user.id !== 0)
                        $('#ctag-' + id).show();
                    $('#c' + id).find('.gravatar').css('width', '32px').css('height', '32px');
                    if (defaultCollapsed) {
                        $('#cc-' + id).hide();
                        $('#ch-' + id).show();
                    }
                }
                else {
                    $('#c' + id).find('.comment-tags').hide();
                    realSpinner.text('+');
                    $('#cr-' + id).hide();
                    if (BUGZILLA.user.id !== 0)
                        $('#ctag-' + id).hide();
                    $('#c' + id).find('.gravatar').css('width', '16px').css('height', '16px');
                    if (defaultCollapsed) {
                        $('#ch-' + id).hide();
                        $('#cc-' + id).show();
                    }
                }
            });
        }
    }

    $('.change-spinner')
        .click(function(event) {
            event.preventDefault();
            toggleChange($(this));
        });

    // view and tag menus

    $('#view-reset')
        .click(function() {
            $('.change-spinner:visible').each(function() {
                toggleChange($(this), 'reset');
            });
        });

    $('#view-collapse-all')
        .click(function() {
            $('.change-spinner:visible').each(function() {
                toggleChange($(this), 'hide');
            });
        });

    $('#view-expand-all')
        .click(function() {
            $('.change-spinner:visible').each(function() {
                toggleChange($(this), 'show');
            });
        });

    $('#view-comments-only')
        .click(function() {
            $('.change-spinner:visible').each(function() {
                toggleChange($(this), this.id.substr(0, 3) === 'cs-' ? 'show' : 'hide');
            });
        });

    $('#view-toggle-cc')
        .click(function() {
            var that = $(this);
            var item = $('.context-menu-item.hover');
            if (that.data('shown') === '1') {
                that.data('shown', '0');
                item.text('Show CC Changes');
                $('.cc-only').hide();
            }
            else {
                that.data('shown', '1');
                item.text('Hide CC Changes');
                $('.cc-only').show();
            }
        });

    $('#view-toggle-treeherder')
        .click(function() {
            var that = $(this);
            console.log(that.data('userid'));
            var item = $('.context-menu-item.hover');
            if (that.data('hidden') === '1') {
                that.data('hidden', '0');
                item.text('Hide Treeherder Comments');
                $('.ca-' + that.data('userid')).show();
            }
            else {
                that.data('hidden', '1');
                item.text('Show Treeherder Comments');
                $('.ca-' + that.data('userid')).hide();
            }
        });

    function updateTagsMenu() {
        var tags = [];
        $('.comment-tags').each(function() {
            $.each(tagsFromDom($(this)), function() {
                var tag = this.toLowerCase();
                if (tag in tags) {
                    tags[tag]++;
                }
                else {
                    tags[tag] = 1;
                }
            });
        });
        var tagNames = Object.keys(tags);
        tagNames.sort();

        var btn = $('#comment-tags-btn');
        if (tagNames.length === 0) {
            btn.hide();
            return;
        }
        btn.show();

        // clear out old li items. Always leave the first one (Reset)
        var $li = $('#comment-tags-menu li');
        for (var i = 1, l = $li.length; i < l; i++) {
            $li.eq(i).remove();
        }

        // add new li items
        $.each(tagNames, function(key, value) {
            $('#comment-tags-menu')
                .append($('<li role="presentation">')
                    .append($('<a role="menuitem" tabindex="-1" data-comment-tag="' + value + '">')
                        .append(value + ' (' + tags[value] + ')')));
        });

        $('a[data-comment-tag]').each(function() {
            $(this).click(function() {
                var $that = $(this);
                var tag = $that.data('comment-tag');
                if (tag === '') {
                    $('.change-spinner:visible').each(function() {
                        toggleChange($(this), 'reset');
                    });
                    return;
                }
                var firstComment = false;
                $('.change-spinner:visible').each(function() {
                    var $that = $(this);
                    var commentTags = tagsFromDom($that.parents('.comment').find('.comment-tags'));
                    var hasTag = $.inArrayIn(tag, commentTags) >= 0;
                    toggleChange($that, hasTag ? 'show' : 'hide');
                    if (hasTag && !firstComment) {
                        firstComment = $that;
                    }
                });
                if (firstComment)
                    $.scrollTo(firstComment);
            });
        });
    }

    //
    // anything after this point is only executed for logged in users
    //

    if (BUGZILLA.user.id === 0) return;

    // comment tagging

    function taggingError(commentNo, message) {
        $('#ctag-' + commentNo + ' .comment-tags').append($('#ctag-error'));
        $('#ctag-error-message').text(message);
        $('#ctag-error').show();
    }

    function deleteTag(event) {
        event.preventDefault();
        $('#ctag-error').hide();

        var that = $(this);
        var comment = that.parents('.comment');
        var commentNo = comment.data('no');
        var commentID = comment.data('id');
        var tag = that.parent('.comment-tag').contents().filter(function() {
            return this.nodeType === 3;
        }).text();
        var container = that.parents('.comment-tags');

        // update ui
        that.parent('.comment-tag').remove();
        renderTags(commentNo, tagsFromDom(container));
        updateTagsMenu();

        // update bugzilla
        bugzilla_ajax(
            {
                url: 'rest/bug/comment/' + commentID + '/tags',
                type: 'PUT',
                data: { remove: [ tag ] },
                hideError: true
            },
            function(data) {
                renderTags(commentNo, data);
                updateTagsMenu();
            },
            function(message) {
                taggingError(commentNo, message);
            }
        );
    }
    $('.comment-tag a').click(deleteTag);

    function tagsFromDom(commentTagsDiv) {
        return commentTagsDiv
            .find('.comment-tag')
            .contents()
            .filter(function() { return this.nodeType === 3; })
            .map(function() { return $(this).text(); })
            .toArray();
    }

    function renderTags(commentNo, tags) {
        cancelRefresh();
        var root = $('#ctag-' + commentNo + ' .comment-tags');
        root.find('.comment-tag').remove();
        $.each(tags, function() {
            var span = $('<span/>').addClass('comment-tag').text(this);
            if (BUGZILLA.user.can_tag) {
                span.prepend($('<a>x</a>').click(deleteTag));
            }
            root.append(span);
        });
        $('#ctag-' + commentNo + ' .comment-tags').append($('#ctag-error'));
    }

    var refreshXHR;

    function refreshTags(commentNo, commentID) {
        cancelRefresh();
        refreshXHR = bugzilla_ajax(
            {
                url: 'rest/bug/comment/' + commentID + '?include_fields=tags',
                hideError: true
            },
            function(data) {
                refreshXHR = false;
                renderTags(commentNo, data.comments[commentID].tags);
            },
            function(message) {
                refreshXHR = false;
                taggingError(commentNo, message);
            }
        );
    }

    function cancelRefresh() {
        if (refreshXHR) {
            refreshXHR.abort();
            refreshXHR = false;
        }
    }

    $('#ctag-add')
        .devbridgeAutocomplete({
            serviceUrl: function(query) {
                return 'rest/bug/comment/tags/' + encodeURIComponent(query);
            },
            params: {
                Bugzilla_api_token: (BUGZILLA.api_token ? BUGZILLA.api_token : '')
            },
            deferRequestBy: 250,
            minChars: 3,
            tabDisabled: true,
            autoSelectFirst: true,
            triggerSelectOnValidInput: false,
            transformResult: function(response) {
                response = $.parseJSON(response);
                return {
                    suggestions: $.map(response, function(tag) {
                        return { value: tag };
                    })
                };
            },
            formatResult: function(suggestion, currentValue) {
                // disable <b> wrapping of matched substring
                return suggestion.value.htmlEncode();
            }
        })
        .keydown(function(event) {
            if (event.which === 27) {
                event.preventDefault();
                $('#ctag-close').click();
            }
            else if (event.which === 13) {
                event.preventDefault();
                $('#ctag-error').hide();

                var ctag = $('#ctag');
                var newTags = $('#ctag-add').val().trim().split(/[ ,]/);
                var commentNo = ctag.data('commentNo');
                var commentID = ctag.data('commentID');

                $('#ctag-close').click();

                // update ui
                var tags = tagsFromDom($(this).parents('.comment-tags'));
                var dirty = false;
                var addTags = [];
                $.each(newTags, function(index, value) {
                    if ($.inArrayIn(value, tags) == -1)
                        addTags.push(value);
                });
                if (addTags.length === 0)
                    return;

                // validate
                try {
                    $.each(addTags, function(index, value) {
                        if (value.length < BUGZILLA.constant.min_comment_tag_length) {
                            throw 'Comment tags must be at least ' +
                                BUGZILLA.constant.min_comment_tag_length + ' characters.';
                        }
                        if (value.length > BUGZILLA.constant.max_comment_tag_length) {
                            throw 'Comment tags cannot be longer than ' +
                                BUGZILLA.constant.min_comment_tag_length + ' characters.';
                        }
                    });
                } catch(ex) {
                    taggingError(commentNo, ex);
                    return;
                }

                Array.prototype.push.apply(tags, addTags);
                tags.sort();
                renderTags(commentNo, tags);

                // update bugzilla
                bugzilla_ajax(
                    {
                        url: 'rest/bug/comment/' + commentID + '/tags',
                        type: 'PUT',
                        data: { add: addTags },
                        hideError: true
                    },
                    function(data) {
                        renderTags(commentNo, data);
                        updateTagsMenu();
                    },
                    function(message) {
                        taggingError(commentNo, message);
                        refreshTags(commentNo, commentID);
                    }
                );
            }
        });

    $('#ctag-close')
        .click(function(event) {
            event.preventDefault();
            $('#ctag').hide().data('commentNo', '');
        });

    $('.tag-btn')
        .click(function(event) {
            event.preventDefault();
            var that = $(this);
            var commentNo = that.data('no');
            var commentID = that.data('id');
            var ctag = $('#ctag');
            $('#ctag-error').hide();

            // toggle -> hide
            if (ctag.data('commentNo') === commentNo) {
                ctag.hide().data('commentNo', '');
                window.focus();
                return;
            }
            ctag.data('commentNo', commentNo);
            ctag.data('commentID', commentID);

            // kick off a refresh of the tags
            refreshTags(commentNo, commentID);

            // expand collapsed comments
            if ($('#ct-' + commentNo + ':visible').length === 0) {
                $('#cs-' + commentNo + ', #ccs-' + commentNo).click();
            }

            // move, show, and focus tagging ui
            ctag.prependTo('#ctag-' + commentNo + ' .comment-tags').show();
            $('#ctag-add').val('').focus();
        });

    $('.close-btn')
        .click(function(event) {
            event.preventDefault();
            $('#' + $(this).data('for')).hide();
        });

    updateTagsMenu();
});
