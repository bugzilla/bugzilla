/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Iterate all comments, and initialize the inline comment editor on each.
 */
Bugzilla.InlineCommentEditorInit = class InlineCommentEditorInit {
  /**
   * Initialize a new InlineCommentEditorInit instance.
   */
  constructor() {
    document.querySelectorAll('.change-set').forEach($change_set => {
      if ($change_set.querySelector('.edit-btn')) {
        new Bugzilla.InlineCommentEditor($change_set);
      }
    });
  }
};

/**
 * Provide the inline comment editing functionality that allows to edit and update a comment on the bug page.
 */
Bugzilla.InlineCommentEditor = class InlineCommentEditor {
  /**
   * Initialize a new InlineCommentEditor instance.
   * @param {HTMLElement} $change_set Comment outer.
   */
  constructor($change_set) {
    this.str = BUGZILLA.string.InlineCommentEditor;
    this.comment_id = Number($change_set.querySelector('.comment').dataset.id);
    this.commenter_id = Number($change_set.querySelector('.email').dataset.userId);

    this.$change_set = $change_set;
    this.$edit_button = $change_set.querySelector('.edit-btn');
    this.$revisions_link = $change_set.querySelector('.change-revisions a');
    this.$body = $change_set.querySelector('.comment-text');

    this.$edit_button.addEventListener('click', event => this.edit_button_onclick(event));
  }

  /**
   * Check if the comment is edited. Ignore leading/trailing white space(s) and/or additional empty line(s) when
   * comparing the changes.
   * @private
   * @readonly
   * @type {Boolean}
   */
  get edited() {
    return this.$textarea.value.trim() !== this.raw_comment.trim();
  }

  /**
   * Check if the user is on the macOS platform.
   * @private
   * @readonly
   * @type {Boolean}
   */
  get on_mac() {
    return navigator.platform === 'MacIntel';
  }

  /**
   * Called whenever the Edit button is clicked.
   * @param {MouseEvent} event Click event.
   */
  edit_button_onclick(event) {
    event.preventDefault();

    this.toggle_toolbar_buttons(true);
    this.$body.hidden = true;

    // Replace the comment body with a disabled `<textarea>` filled with the text as a placeholder while retrieving the
    // raw comment text
    this.$body.insertAdjacentHTML('afterend',
      `<textarea class="comment-editor-textarea" disabled>${this.$body.textContent}</textarea>`);
    this.$textarea = this.$body.nextElementSibling;
    this.$textarea.style.height = `${this.$textarea.scrollHeight}px`;

    // Insert a toolbar that provides the Save and Cancel buttons as well as the Hide This Revision checkbox for admin
    this.$textarea.insertAdjacentHTML('afterend',
      `
      <div role="toolbar" class="comment-editor-toolbar" aria-label="${this.str.toolbar}">
        ${BUGZILLA.user.is_insider && BUGZILLA.user.id !== this.commenter_id ? `
          <label><input type="checkbox" value="on" checked> ${this.str.hide_revision}</label>` : ''}
        <button type="button" class="minor" data-action="cancel" title="${this.str.cancel_tooltip} (Esc)"
                aria-keyshortcuts="Escape">${this.str.cancel}</button>
        <button type="button" class="major" disabled data-action="save"
                title="${this.str.save_tooltip} (${this.on_mac ? '&#x2318;Return' : 'Ctrl+Enter'})"
                aria-keyshortcuts="${this.on_mac ? 'Meta+Enter' : 'Ctrl+Enter'}">${this.str.save}</button>
      </div>
      `
    );
    this.$toolbar = this.$textarea.nextElementSibling;

    this.$save_button = this.$toolbar.querySelector('button[data-action="save"]');
    this.$cancel_button = this.$toolbar.querySelector('button[data-action="cancel"]');
    this.$is_hidden_checkbox = this.$toolbar.querySelector('input[type="checkbox"]');

    this.$textarea.addEventListener('input', event => this.textarea_oninput(event));
    this.$textarea.addEventListener('keydown', event => this.textarea_onkeydown(event));
    this.$save_button.addEventListener('click', () => this.save());
    this.$cancel_button.addEventListener('click', () => this.finish());

    // Retrieve the raw comment text
    bugzilla_ajax({
      url: `${BUGZILLA.config.basepath}rest/editcomments/comment/${this.comment_id}`,
      hideError: true,
    }, data => {
      this.fetch_onload(data);
    }, message => {
      this.fetch_onerror(message);
    });
  }

  /**
   * Called whenever the comment `<textarea>` is edited. Enable or disable the Save button depending on the content.
   * @param {KeyboardEvent} event `input` event.
   */
  textarea_oninput(event) {
    if (event.isComposing) {
      return;
    }

    this.$save_button.disabled = !this.edited || !!this.$textarea.value.match(/^\s*$/);
  }

  /**
   * Called whenever any key is pressed on the comment `<textarea>`. Handle a couple of shortcut keys.
   * @param {KeyboardEvent} event `keydown` event.
   */
  textarea_onkeydown(event) {
    if (event.isComposing) {
      return;
    }

    const { key, altKey, ctrlKey, metaKey, shiftKey } = event;
    const accelKey = this.on_mac ? metaKey && !ctrlKey : ctrlKey;

    // Accel + Enter = Save
    if (key === 'Enter' && accelKey && !altKey && !shiftKey) {
      this.save();
    }

    // Escape = Cancel
    if (key === 'Escape' && !accelKey && !altKey && !shiftKey) {
      this.finish();
    }
  }

  /**
   * Called whenever the Update Comment button is clicked. Upload the changes to the server.
   */
  save() {
    if (!this.edited) {
      return;
    }

    // Disable the `<textarea>` and Save button while waiting for the response
    this.$textarea.disabled = this.$save_button.disabled = true;
    this.$save_button.textContent = this.str.saving;

    bugzilla_ajax({
      url: `${BUGZILLA.config.basepath}rest/editcomments/comment/${this.comment_id}`,
      type: 'PUT',
      hideError: true,
      data: {
        new_comment: this.$textarea.value,
        is_hidden: this.$is_hidden_checkbox && this.$is_hidden_checkbox.checked ? 1 : 0,
      },
    }, data => {
      this.save_onsuccess(data);
    }, message => {
      this.save_onerror(message);
    });
  }

  /**
   * Finish editing by restoring the UI, once editing is complete or cancelled. Any unsaved comment will be discarded.
   */
  finish() {
    this.toggle_toolbar_buttons(false);
    this.$edit_button.focus();
    this.$body.hidden = false;
    this.$textarea.remove();
    this.$toolbar.remove();
  }

  /**
   * Enable or disable buttons on the comment actions toolbar (not the editor's own toolbar) while editing the comment
   * to avoid any unexpected behaviour.
   * @param {Boolean} disabled Whether the buttons should be disabled.
   */
  toggle_toolbar_buttons(disabled) {
    this.$change_set.querySelectorAll('.comment-actions button').forEach($button => $button.disabled = disabled);
  }

  /**
   * Called whenever a raw comment text is successfully retrieved. Fill in the `<textarea>` so user can start editing.
   * @param {Object} data Response data.
   */
  fetch_onload(data) {
    this.$textarea.value = this.raw_comment = data.comments[this.comment_id];
    this.$textarea.style.height = `${this.$textarea.scrollHeight}px`;
    this.$textarea.disabled = false;
    this.$textarea.focus();
    this.$textarea.selectionStart = this.$textarea.value.length;

    // Add `name` attribute to form widgets so the revision can also be submitted while saving the entire bug
    this.$textarea.name = `edit_comment_textarea_${this.comment_id}`;
    this.$is_hidden_checkbox ? this.$is_hidden_checkbox.name = `edit_comment_checkbox_${this.comment_id}` : '';
  }

  /**
   * Called whenever a raw comment text could not be retrieved. Restore the UI, and display an error message.
   * @param {String} message Error message.
   */
  fetch_onerror(message) {
    this.finish();
    window.alert(`${this.str.fetch_error}\n\n${message}`);
  }

  /**
   * Called whenever an updated comment is successfully saved. Restore the UI, and insert/update the revision link.
   * @param {Object} data Response data.
   */
  save_onsuccess(data) {
    this.$body.innerHTML = data.html;
    this.finish();

    if (!this.$revisions_link) {
      const $time = this.$change_set.querySelector('.change-time');
      const params = new URLSearchParams({
        id: 'comment-revisions.html',
        bug_id: BUGZILLA.bug_id,
        comment_id: this.comment_id,
      });

      $time.insertAdjacentHTML('afterend',
        `
        &bull;
        <div class="change-revisions">
          <a href="${BUGZILLA.config.basepath}page.cgi?${params.toString().htmlEncode()}">${this.str.edited}</a>
        </div>
        `
      );
      this.$revisions_link = $time.nextElementSibling.querySelector('a');
    }

    this.$revisions_link.title = this.str.revision_count[data.count === 1 ? 0 : 1].replace('%d', data.count);
  }

  /**
   * Called whenever an updated comment could not be saved. Re-enable the `<textarea>` and Save button, and display an
   * error message.
   * @param {String} message Error message.
   */
  save_onerror(message) {
    this.$textarea.disabled = this.$save_button.disabled = false;
    this.$save_button.textContent = this.str.save;

    window.alert(`${this.str.save_error}\n\n${message}`);
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.InlineCommentEditorInit());
