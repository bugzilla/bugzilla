/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    'use strict';

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
            $('#ct-' + id + ', #ctag-' + id).slideToggle('fast', function() {
                $('#c' + id).find('.activity').toggle();
                spinner.text($('#ct-' + id + ':visible').length ? '-' : '+');
            });
        });

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
});
