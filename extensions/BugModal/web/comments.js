/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

$(function() {
    'use strict';

    // comment collapse/expand

    const update_spinner = (spinner, expanded) => {
        const str = spinner.data('strings');

        spinner.attr({
            'title': expanded ? str.collapse_tooltip : str.expand_tooltip,
            'aria-label': expanded ? str.collapse_label : str.expand_label,
            'aria-expanded': expanded,
        });
    };

    function toggleChange(spinner, forced) {
        var spinnerID = spinner.attr('id');
        var id = spinnerID.substring(spinnerID.indexOf('-') + 1);

        // non-comment toggle
        if (spinnerID.substr(0, 1) == 'a') {
            var changeSet = spinner.parents('.change-set');
            if (forced == 'hide') {
                changeSet.find('.activity').hide();
                changeSet.find('.gravatar').css('width', '16px').css('height', '16px');
                $('#ar-' + id).hide();
                update_spinner(spinner, false);
            }
            else if (forced == 'show' || forced == 'reset') {
                changeSet.find('.activity').show();
                changeSet.find('.gravatar').css('width', '32px').css('height', '32px');
                $('#ar-' + id).show();
                update_spinner(spinner, true);
            }
            else {
                changeSet.find('.activity').slideToggle('fast', function() {
                    $('#ar-' + id).toggle();
                    if (changeSet.find('.activity' + ':visible').length) {
                        changeSet.find('.gravatar').css('width', '32px').css('height', '32px');
                        update_spinner(spinner, true);
                    }
                    else {
                        changeSet.find('.gravatar').css('width', '16px').css('height', '16px');
                        update_spinner(spinner, false);
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
            $('#c' + id).find('.activity, .attachment, .comment-tags').hide();
            $('#c' + id).find('.gravatar').css('width', '16px').css('height', '16px');
            $('#cr-' + id).hide();
            update_spinner(realSpinner, false);
        }
        else if (forced == 'show') {
            if (defaultCollapsed) {
                $('#cc-' + id).hide();
                $('#ch-' + id).show();
            }
            $('#ct-' + id).show();
            if (BUGZILLA.user.id !== 0)
                $('#ctag-' + id).show();
            $('#c' + id).find('.activity, .attachment, .comment-tags').show();
            $('#c' + id).find('.gravatar').css('width', '32px').css('height', '32px');
            $('#cr-' + id).show();
            update_spinner(realSpinner, true);
        }
        else {
            $('#ct-' + id).slideToggle('fast', function() {
                $('#c' + id).find('.activity').toggle();
                $('#c' + id).find('.attachment').slideToggle();
                if ($('#ct-' + id + ':visible').length) {
                    $('#c' + id).find('.comment-tags').show();
                    update_spinner(realSpinner, true);
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
                    update_spinner(realSpinner, false);
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

    $('#view-toggle-treeherder')
        .click(function() {
            var that = $(this);
            var userids = that.data('userids');
            if (that.data('hidden') === '0') {
                that.data('hidden', '1');
                that.text('Show Treeherder Comments');
                userids.forEach((id) => {
                    $('.ca-' + id).each(function() {
                        toggleChange($(this).find('.default-collapsed .change-spinner').first(), 'hide');
                    });
                });
            }
            else {
                that.data('hidden', '0');
                that.text('Hide Treeherder Comments');
                userids.forEach((id) => {
                    $('.ca-' + id).each(function() {
                        toggleChange($(this).find('.default-collapsed .change-spinner').first(), 'show');
                    });
                });
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
                url: `${BUGZILLA.config.basepath}rest/bug/comment/${commentID}/tags`,
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
                url: `${BUGZILLA.config.basepath}rest/bug/comment/${commentID}?include_fields=tags`,
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
            appendTo: $('#main-inner'),
            forceFixPosition: true,
            serviceUrl: function(query) {
                return `${BUGZILLA.config.basepath}rest/bug/comment/tags/${encodeURIComponent(query)}`;
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
                        url: `${BUGZILLA.config.basepath}rest/bug/comment/${commentID}/tags`,
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

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {};

/**
 * Reference or define the Review namespace.
 * @namespace
 */
Bugzilla.BugModal = Bugzilla.BugModal || {};

/**
 * Implement the modal bug view's comment-related functionality.
 */
Bugzilla.BugModal.Comments = class Comments {
  /**
   * Initiate a new Comments instance.
   */
  constructor() {
    this.prepare_inline_attachments();
  }

  /**
   * Prepare to show image and text attachments inline if possible. For a better performance, this functionality uses
   * the Intersection Observer API to show attachments when the associated comment goes into the viewport, when the page
   * is scrolled down or the collapsed comment is expanded. This also utilizes the Network Information API to save
   * bandwidth over cellular networks.
   * @see https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API
   * @see https://developer.mozilla.org/en-US/docs/Web/API/Network_Information_API
   */
  prepare_inline_attachments() {
    // Check the user setting, API support and connectivity
    if (!BUGZILLA.user.settings.inline_attachments || typeof IntersectionObserver !== 'function' ||
        (navigator.connection && navigator.connection.type === 'cellular')) {
      return;
    }

    const observer = new IntersectionObserver(entries => entries.forEach(entry => {
      const $att = entry.target;

      if (entry.intersectionRatio > 0) {
        observer.unobserve($att);
        this.show_attachment($att);
      }
    }), { root: document.querySelector('#bugzilla-body') });

    // Show only non-obsolete attachments
    document.querySelectorAll('.change-set .attachment:not(.obsolete)').forEach($att => observer.observe($att));
  }

  /**
   * Load and show an image, audio, video or text attachment.
   * @param {HTMLElement} $att An attachment wrapper element.
   */
  async show_attachment($att) {
    const id = Number($att.dataset.id);
    const link = $att.querySelector('.link').href;
    const name = $att.querySelector('[itemprop="name"]').textContent;
    const type = $att.querySelector('[itemprop="encodingFormat"]').content;
    const size = Number($att.querySelector('[itemprop="contentSize"]').content);
    const max_size = 2000000;

    // Show image smaller than 2 MB
    if (type.match(/^image\/(?!vnd).+$/) && size < max_size) {
      $att.insertAdjacentHTML('beforeend', `
        <a href="${link}" class="outer lightbox"><img src="${link}" alt="${name}" itemprop="image"></a>`);

      // Add lightbox support
      $att.querySelector('.outer.lightbox').addEventListener('click', event => {
        if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) {
          return;
        }

        event.preventDefault();
        lb_show(event.target);
      });
    }

    // Show audio and video
    if (type.match(/^(?:audio|video)\/(?!vnd).+$/)) {
      const media = type.split('/')[0];

      if (document.createElement(media).canPlayType(type)) {
        $att.insertAdjacentHTML('beforeend', `
          <span class="outer"><${media} src="${link}" controls itemprop="${media}"></span>`);
      }
    }

    // Detect text (code from attachment.js)
    const is_patch = !!name.match(/\.(?:diff|patch)$/) || !!type.match(/^text\/x-(?:diff|patch)$/);
    const is_markdown = !!name.match(/\.(?:md|mkdn?|mdown|markdown)$/);
    const is_source = !!name.match(/\.(?:cpp|es|h|js|json|rs|rst|sh|toml|ts|tsx|xml|yaml|yml)$/);
    const is_text = type.startsWith('text/') || is_patch || is_markdown || is_source;

    // Show text smaller than 2 MB
    if (is_text && size < max_size) {
      // Load text body
      try {
        const response = await fetch(`/attachment.cgi?id=${id}`, { credentials: 'same-origin' });

        if (!response.ok) {
          throw new Error();
        }

        const text = await response.text();
        const lang = is_patch ? 'diff' : type.match(/\w+$/)[0];

        $att.insertAdjacentHTML('beforeend', `
          <a href="${link}" title="${name}" class="outer">
          <pre class="language-${lang}" role="img" itemprop="text">${text}</pre></a>`);

        if (Prism) {
          Prism.highlightElement($att.querySelector('pre'));
        }
      } catch (ex) {}
    }
  }
};

document.addEventListener('DOMContentLoaded', () => new Bugzilla.BugModal.Comments(), { once: true });
