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

    async function deleteTag(event) {
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

        // update Bugzilla
        try {
            renderTags(commentNo, await Bugzilla.API.put(`bug/comment/${commentID}/tags`, { remove: [tag] }));
            updateTagsMenu();
        } catch ({ message }) {
            taggingError(commentNo, message);
        }
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
                span.prepend($('<a role="button" aria-label="Remove">x</a>').click(deleteTag));
            }
            root.append(span);
        });
        $('#ctag-' + commentNo + ' .comment-tags').append($('#ctag-error'));
        $(`.comment[data-no="${commentNo}"]`).attr('data-tags', tags.join(' '));
    }

    let abort_controller;

    const refreshTags = async (commentNo, commentID) => {
        cancelRefresh();

        try {
            abort_controller = new AbortController();

            const { signal } = abort_controller;
            const { comments } = await Bugzilla.API.get(`bug/comment/${commentID}`, {
              include_fields: ['tags'],
            }, { signal });

            renderTags(commentNo, comments[commentID].tags);
        } catch ({ name, message }) {
            if (name !== 'AbortError') {
                taggingError(commentNo, message);
            }
        } finally {
            abort_controller = undefined;
        }
    }

    function cancelRefresh() {
        if (abort_controller) {
            abort_controller.abort();
            abort_controller = undefined;
        }
    }

    $('#ctag-add')
        .devbridgeAutocomplete({
            appendTo: $('#main-inner'),
            forceFixPosition: true,
            deferRequestBy: 250,
            minChars: 3,
            tabDisabled: true,
            autoSelectFirst: true,
            triggerSelectOnValidInput: false,
            lookup: (query, done) => {
                // Note: `async` doesn't work for this `lookup` function, so use a `Promise` chain instead
                Bugzilla.API.get(`bug/comment/tags/${encodeURIComponent(query)}`)
                    .then(data => data.map(tag => ({ value: tag })))
                    .catch(() => [])
                    .then(suggestions => done({ suggestions }));
            },
            formatResult: function(suggestion, currentValue) {
                // disable <b> wrapping of matched substring
                return suggestion.value.htmlEncode();
            }
        })
        .keydown(async event => {
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

                // update Bugzilla
                try {
                    renderTags(commentNo, await Bugzilla.API.put(`bug/comment/${commentID}/tags`, { add: addTags }));
                    updateTagsMenu();
                } catch ({ message }) {
                    taggingError(commentNo, message);
                    refreshTags(commentNo, commentID);
                }
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
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

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
   * Prepare to show an attachment inline if possible.
   */
  prepare_inline_attachments() {
    // Check the connectivity, API support, user setting, bug security and sensitive keywords
    if ((navigator.connection && navigator.connection.type === 'cellular') ||
        typeof IntersectionObserver !== 'function' || !BUGZILLA.user.settings.inline_attachments ||
        BUGZILLA.bug_secure ||
        BUGZILLA.bug_keywords.split(', ').find(keyword => keyword.match(/^(hang|assertion|crash)$/))) {
      return;
    }

    document.querySelectorAll('.change-set').forEach($set => {
      // Skip if the comment has the `hide-attachment` tag
      const $comment = $set.querySelector('.comment:not([data-tags~="hide-attachment"])');
      // Skip if the attachment is obsolete or deleted
      const $attachment = $set.querySelector('.attachment:not(.obsolete):not(.deleted)');

      if ($comment && $attachment) {
        this.attachment = new Bugzilla.InlineAttachment($attachment);
      }
    });
  }
};

/**
 * Implement the inline attachment renderer that will be used for bug comments. For a better performance, this
 * functionality uses the Intersection Observer API to show an attachment when the comment goes into the viewport.
 */
Bugzilla.InlineAttachment = class InlineAttachment {
  /**
   * Initiate a new InlineAttachment instance.
   * @param {HTMLElement} $attachment Attachment container on each comment.
   */
  constructor($attachment) {
    this.$attachment = $attachment;
    this.id = Number(this.$attachment.dataset.id);
    this.link = this.$attachment.querySelector('.link').href;
    this.name = this.$attachment.querySelector('[itemprop="name"]').content;
    this.size = Number(this.$attachment.querySelector('[itemprop="contentSize"]').content);
    this.type = this.$attachment.querySelector('[itemprop="encodingFormat"]').content;
    this.media = this.type.split('/').shift();

    // Show image smaller than 2 MB, excluding SVG and non-standard formats
    if (this.type.match(/^image\/(?!vnd|svg).+$/) && this.size < 2000000) {
      this.show_image();
    }

    // Show audio and video
    if (this.type.match(/^(?:audio|video)\/(?!vnd).+$/) && document.createElement(this.media).canPlayType(this.type)) {
      this.show_media();
    }

    // Detect text (code from attachment.js)
    this.is_patch = this.$attachment.matches('.patch');
    this.is_markdown = !!this.name.match(/\.(?:md|mkdn?|mdown|markdown)$/);
    this.is_source = !!this.name.match(/\.(?:cpp|es|h|js|json|rs|rst|sh|toml|ts|tsx|xml|yaml|yml)$/);
    this.is_text = this.type.match(/^text\/(?!x-).+$/) || this.is_patch || this.is_markdown || this.is_source;

    // Show text smaller than 50 KB
    if (this.is_text && this.size < 50000) {
      this.show_text();
    }
  }

  /**
   * Show an image attachment.
   */
  async show_image() {
    // Insert a placeholder first
    this.$attachment.insertAdjacentHTML('beforeend', `<a href="${this.link}" class="outer lightbox"></a>`);

    // Wait until the container goes into the viewport
    await this.watch_visibility();

    const $image = new Image();

    try {
      await new Promise((resolve, reject) => {
        $image.addEventListener('load', () => resolve(), { once: true });
        $image.addEventListener('error', () => reject(), { once: true });
        $image.src = this.link;
      });

      $image.setAttribute('itemprop', 'image');
      $image.alt = this.name;
      this.$outer.appendChild($image);

      // Add lightbox support
      this.$outer.addEventListener('click', event => {
        if (!event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey) {
          event.preventDefault();
          lb_show(event.target);
        }
      });
    } catch (ex) {
      this.$outer.remove();
    }
  }

  /**
   * Show an audio or video attachment.
   */
  async show_media() {
    // Insert a placeholder first
    this.$attachment.insertAdjacentHTML('beforeend', '<span class="outer"></span>');

    // Wait until the container goes into the viewport
    await this.watch_visibility();

    const $media = document.createElement(this.media);

    try {
      await new Promise((resolve, reject) => {
        $media.addEventListener('loadedmetadata', () => resolve(), { once: true });
        $media.addEventListener('error', () => reject(), { once: true });
        $media.src = this.link;
      });

      $media.setAttribute('itemprop', this.media);
      $media.controls = true;
      this.$outer.appendChild($media);
    } catch (ex) {
      this.$outer.remove();
    }
  }

  /**
   * Show a text attachment. Fetch the raw text via the API.
   */
  async show_text() {
    // Insert a placeholder first
    this.$attachment.insertAdjacentHTML('beforeend',
      `<button type="button" role="link" title="${this.name.htmlEncode()}" class="outer"></button>`);

    // Wait until the container goes into the viewport
    await this.watch_visibility();

    try {
      const { attachments } = await Bugzilla.API.get(`bug/attachment/${this.id}`, { include_fields: 'data' });
      const text = decodeURIComponent(escape(atob(attachments[this.id].data)));
      const lang = this.is_patch ? 'diff' : this.type.match(/\w+$/)[0];

      this.$outer.innerHTML = `<pre class="language-${lang}" role="img" itemprop="text">${text.htmlEncode()}</pre>`;

      // Make the button work as a link. It cannot be `<a>` because Prism Autolinker plugin may add links to `<pre>`
      this.$attachment.querySelector('[role="link"]').addEventListener('click', () => location.href = this.link);

      if (Prism) {
        Prism.highlightElement(this.$attachment.querySelector('pre'));
        this.$attachment.querySelectorAll('pre a').forEach($a => $a.tabIndex = -1);
      }
    } catch (ex) {
      this.$outer.remove();
    }
  }

  /**
   * Use the Intersection Observer API to watch the visibility of the attachment container.
   * @returns {Promise} Resolved once the container goes into the viewport.
   * @see https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API
   */
  async watch_visibility() {
    this.$outer = this.$attachment.querySelector('.outer');

    return new Promise(resolve => {
      const observer = new IntersectionObserver(entries => entries.forEach(entry => {
        if (entry.intersectionRatio > 0) {
          observer.disconnect();
          resolve();
        }
      }), { root: document.querySelector('#bugzilla-body') });

      observer.observe(this.$attachment);
    });
  }
};

document.addEventListener('DOMContentLoaded', () => new Bugzilla.BugModal.Comments(), { once: true });
