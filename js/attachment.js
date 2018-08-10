/* The contents of this file are subject to the Mozilla Public
 * License Version 1.1 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy of
 * the License at http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS
 * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * The Original Code is the Bugzilla Bug Tracking System.
 *
 * The Initial Developer of the Original Code is Netscape Communications
 * Corporation. Portions created by Netscape are
 * Copyright (C) 1998 Netscape Communications Corporation. All
 * Rights Reserved.
 *
 * Contributor(s): Myk Melez <myk@mozilla.org>
 *                 Joel Peshkin <bugreport@peshkin.net>
 *                 Erik Stambaugh <erik@dasbistro.com>
 *                 Marc Schumann <wurblzap@gmail.com>
 *                 Guy Pyrzak <guy.pyrzak@gmail.com>
 *                 Kohei Yoshino <kohei.yoshino@gmail.com>
 */

function updateCommentPrivacy(checkbox) {
    var text_elem = document.getElementById('comment');
    if (checkbox.checked) {
        text_elem.className='bz_private';
    } else {
        text_elem.className='';
    }
}

/* Functions used when viewing patches in Diff mode. */

function collapse_all() {
  var elem = document.checkboxform.firstChild;
  while (elem != null) {
    if (elem.firstChild != null) {
      var tbody = elem.firstChild.nextSibling;
      if (tbody.className == 'file') {
        tbody.className = 'file_collapse';
        twisty = get_twisty_from_tbody(tbody);
        twisty.firstChild.nodeValue = '(+)';
        twisty.nextSibling.checked = false;
      }
    }
    elem = elem.nextSibling;
  }
  return false;
}

function expand_all() {
  var elem = document.checkboxform.firstChild;
  while (elem != null) {
    if (elem.firstChild != null) {
      var tbody = elem.firstChild.nextSibling;
      if (tbody.className == 'file_collapse') {
        tbody.className = 'file';
        twisty = get_twisty_from_tbody(tbody);
        twisty.firstChild.nodeValue = '(-)';
        twisty.nextSibling.checked = true;
      }
    }
    elem = elem.nextSibling;
  }
  return false;
}

var current_restore_elem;

function restore_all() {
  current_restore_elem = null;
  incremental_restore();
}

function incremental_restore() {
  if (!document.checkboxform.restore_indicator.checked) {
    return;
  }
  var next_restore_elem;
  if (current_restore_elem) {
    next_restore_elem = current_restore_elem.nextSibling;
  } else {
    next_restore_elem = document.checkboxform.firstChild;
  }
  while (next_restore_elem != null) {
    current_restore_elem = next_restore_elem;
    if (current_restore_elem.firstChild != null) {
      restore_elem(current_restore_elem.firstChild.nextSibling);
    }
    next_restore_elem = current_restore_elem.nextSibling;
  }
}

function restore_elem(elem, alertme) {
  if (elem.className == 'file_collapse') {
    twisty = get_twisty_from_tbody(elem);
    if (twisty.nextSibling.checked) {
      elem.className = 'file';
      twisty.firstChild.nodeValue = '(-)';
    }
  } else if (elem.className == 'file') {
    twisty = get_twisty_from_tbody(elem);
    if (!twisty.nextSibling.checked) {
      elem.className = 'file_collapse';
      twisty.firstChild.nodeValue = '(+)';
    }
  }
}

function twisty_click(twisty) {
  tbody = get_tbody_from_twisty(twisty);
  if (tbody.className == 'file') {
    tbody.className = 'file_collapse';
    twisty.firstChild.nodeValue = '(+)';
    twisty.nextSibling.checked = false;
  } else {
    tbody.className = 'file';
    twisty.firstChild.nodeValue = '(-)';
    twisty.nextSibling.checked = true;
  }
  return false;
}

function get_tbody_from_twisty(twisty) {
  return twisty.parentNode.parentNode.parentNode.nextSibling;
}
function get_twisty_from_tbody(tbody) {
  return tbody.previousSibling.firstChild.nextSibling.firstChild.firstChild;
}

var prev_mode = 'raw';
var current_mode = 'raw';
var has_edited = 0;
var has_viewed_as_diff = 0;
function editAsComment(patchviewerinstalled)
{
    switchToMode('edit', patchviewerinstalled);
    has_edited = 1;
}
function undoEditAsComment(patchviewerinstalled)
{
    switchToMode(prev_mode, patchviewerinstalled);
}
function redoEditAsComment(patchviewerinstalled)
{
    switchToMode('edit', patchviewerinstalled);
}

function viewDiff(attachment_id, patchviewerinstalled)
{
    switchToMode('diff', patchviewerinstalled);

    // If we have not viewed as diff before, set the view diff frame URL
    if (!has_viewed_as_diff) {
      var viewDiffFrame = document.getElementById('viewDiffFrame');
      viewDiffFrame.src =
          'attachment.cgi?id=' + attachment_id + '&action=diff&headers=0';
      has_viewed_as_diff = 1;
    }
}

function viewRaw(patchviewerinstalled)
{
    switchToMode('raw', patchviewerinstalled);
}

function switchToMode(mode, patchviewerinstalled)
{
    if (mode == current_mode) {
      alert('switched to same mode!  This should not happen.');
      return;
    }

    // Switch out of current mode
    if (current_mode == 'edit') {
      hideElementById('editFrame');
      hideElementById('undoEditButton');
    } else if (current_mode == 'raw') {
      hideElementById('viewFrame');
      if (patchviewerinstalled)
          hideElementById('viewDiffButton');
      hideElementById(has_edited ? 'redoEditButton' : 'editButton');
      hideElementById('smallCommentFrame');
    } else if (current_mode == 'diff') {
      if (patchviewerinstalled)
          hideElementById('viewDiffFrame');
      hideElementById('viewRawButton');
      hideElementById(has_edited ? 'redoEditButton' : 'editButton');
      hideElementById('smallCommentFrame');
    }

    // Switch into new mode
    if (mode == 'edit') {
      showElementById('editFrame');
      showElementById('undoEditButton');
    } else if (mode == 'raw') {
      showElementById('viewFrame');
      if (patchviewerinstalled)
          showElementById('viewDiffButton');

      showElementById(has_edited ? 'redoEditButton' : 'editButton');
      showElementById('smallCommentFrame');
    } else if (mode == 'diff') {
      if (patchviewerinstalled)
        showElementById('viewDiffFrame');

      showElementById('viewRawButton');
      showElementById(has_edited ? 'redoEditButton' : 'editButton');
      showElementById('smallCommentFrame');
    }

    prev_mode = current_mode;
    current_mode = mode;
}

function hideElementById(id)
{
  var elm = document.getElementById(id);
  if (elm) {
    YAHOO.util.Dom.addClass(elm, 'bz_default_hidden');
  }
}

function showElementById(id)
{
  var elm = document.getElementById(id);
  if (elm) {
    YAHOO.util.Dom.removeClass(elm, 'bz_default_hidden');
  }
}

function normalizeComments()
{
  // Remove the unused comment field from the document so its contents
  // do not get transmitted back to the server.

  var small = document.getElementById('smallCommentFrame');
  var big = document.getElementById('editFrame');
  if ( (small) && YAHOO.util.Dom.hasClass(small, 'bz_default_hidden') )
  {
    small.parentNode.removeChild(small);
  }
  if ( (big) && YAHOO.util.Dom.hasClass(big, 'bz_default_hidden') )
  {
    big.parentNode.removeChild(big);
  }
}

function toggle_attachment_details_visibility ( )
{
    // show hide classes
    var container = document.getElementById('attachment_info');
    if( YAHOO.util.Dom.hasClass(container, 'read') ){
        YAHOO.util.Dom.replaceClass(container, 'read', 'edit');
    }else{
        YAHOO.util.Dom.replaceClass(container, 'edit', 'read');
    }
}

/* Used in bug/create.html.tmpl to show/hide the attachment field. */

function handleWantsAttachment(wants_attachment) {
    if (wants_attachment) {
        hideElementById('attachment_false');
        showElementById('attachment_true');
    }
    else {
        showElementById('attachment_false');
        hideElementById('attachment_true');
        bz_attachment_form.reset_fields();
    }

    bz_attachment_form.update_requirements(wants_attachment);
}

/**
 * Expose an `AttachmentForm` instance on global.
 */
var bz_attachment_form;

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {};

/**
 * Implement the attachment selector functionality that can be used standalone or on the New Bug page. This supports 3
 * input methods: traditional `<input type="file">` field, drag & dropping of a file or text, as well as copy & pasting
 * an image or text.
 */
Bugzilla.AttachmentForm = class AttachmentForm {
  /**
   * Initialize a new `AttachmentForm` instance.
   */
  constructor() {
    this.$file = document.querySelector('#att-file');
    this.$data = document.querySelector('#att-data');
    this.$filename = document.querySelector('#att-filename');
    this.$dropbox = document.querySelector('#att-dropbox');
    this.$browse_label = document.querySelector('#att-browse-label');
    this.$textarea = document.querySelector('#att-textarea');
    this.$preview = document.querySelector('#att-preview');
    this.$preview_name = this.$preview.querySelector('[itemprop="name"]');
    this.$preview_type = this.$preview.querySelector('[itemprop="encodingFormat"]');
    this.$preview_text = this.$preview.querySelector('[itemprop="text"]');
    this.$preview_image = this.$preview.querySelector('[itemprop="image"]');
    this.$remove_button = document.querySelector('#att-remove-button');
    this.$description = document.querySelector('#att-description');
    this.$error_message = document.querySelector('#att-error-message');
    this.$ispatch = document.querySelector('#att-ispatch');
    this.$type_outer = document.querySelector('#att-type-outer');
    this.$type_list = document.querySelector('#att-type-list');
    this.$type_manual = document.querySelector('#att-type-manual');
    this.$type_select = document.querySelector('#att-type-select');
    this.$type_input = document.querySelector('#att-type-input');
    this.$isprivate = document.querySelector('#isprivate');
    this.$takebug = document.querySelector('#takebug');

    // Add event listeners
    this.$file.addEventListener('change', () => this.file_onchange());
    this.$dropbox.addEventListener('dragover', event => this.dropbox_ondragover(event));
    this.$dropbox.addEventListener('dragleave', () => this.dropbox_ondragleave());
    this.$dropbox.addEventListener('dragend', () => this.dropbox_ondragend());
    this.$dropbox.addEventListener('drop', event => this.dropbox_ondrop(event));
    this.$browse_label.addEventListener('click', () => this.$file.click());
    this.$textarea.addEventListener('input', () => this.textarea_oninput());
    this.$textarea.addEventListener('paste', event => this.textarea_onpaste(event));
    this.$remove_button.addEventListener('click', () => this.remove_button_onclick());
    this.$description.addEventListener('input', () => this.description_oninput());
    this.$description.addEventListener('change', () => this.description_onchange());
    this.$ispatch.addEventListener('change', () => this.ispatch_onchange());
    this.$type_select.addEventListener('change', () => this.type_select_onchange());
    this.$type_input.addEventListener('change', () => this.type_input_onchange());

    // Prepare the file reader
    this.data_reader = new FileReader();
    this.text_reader = new FileReader();
    this.data_reader.addEventListener('load', () => this.data_reader_onload());
    this.text_reader.addEventListener('load', () => this.text_reader_onload());

    // Initialize the view
    this.enable_keyboard_access();
    this.reset_fields();
  }

  /**
   * Enable keyboard access on the buttons. Treat the Enter keypress as a click.
   */
  enable_keyboard_access() {
    document.querySelectorAll('#att-selector [role="button"]').forEach($button => {
      $button.addEventListener('keypress', event => {
        if (!event.isComposing && event.key === 'Enter') {
          event.target.click();
        }
      });
    });
  }

  /**
   * Reset all the input fields to the initial state, and remove the preview and message.
   */
  reset_fields() {
    this.description_override = false;
    this.$file.value = this.$data.value = this.$filename.value = this.$type_input.value = this.$description.value = '';
    this.$type_list.checked = this.$type_select.options[0].selected = true;

    if (this.$isprivate) {
      this.$isprivate.checked = this.$isprivate.disabled = false;
    }

    if (this.$takebug) {
      this.$takebug.checked = this.$takebug.disabled = false;
    }

    this.clear_preview();
    this.clear_error();
    this.update_requirements();
    this.update_text();
    this.update_ispatch();
  }

  /**
   * Update the `required` property on the Base64 data and Description fields.
   * @param {Boolean} [required=true] `true` if these fields are required, `false` otherwise.
   */
  update_requirements(required = true) {
    this.$data.required = this.$description.required = required;
    this.update_validation();
  }

  /**
   * Update the custom validation message on the Base64 data field depending on the requirement and value.
   */
  update_validation() {
    this.$data.setCustomValidity(this.$data.required && !this.$data.value ? 'Please select a file or enter text.' : '');

    // In Firefox, the message won't be displayed once the field becomes valid then becomes invalid again. This is a
    // workaround for the issue.
    this.$data.hidden = false;
    this.$data.hidden = true;
  }

  /**
   * Process a user-selected file for upload. Read the content if it's been transferred with a paste or drag operation.
   * Update the Description, Content Type, etc. and show the preview.
   * @param {File} file A file to be read.
   * @param {Boolean} [transferred=true] `true` if the source is `DataTransfer`, `false` if it's been selected via
   * `<input type="file">`.
   */
  process_file(file, transferred = true) {
    // Check for patches which should have the `text/plain` MIME type
    const is_patch = !!file.name.match(/\.(?:diff|patch)$/) || !!file.type.match(/^text\/x-(?:diff|patch)$/);
    // Check for text files which may have no MIME type or `application/*` MIME type
    const is_text = !!file.name.match(/\.(?:cpp|es|h|js|json|markdown|md|rs|rst|sh|toml|ts|tsx|xml|yaml|yml)$/);
    // Reassign the MIME type
    const type = is_patch || (is_text && !file.type) ? 'text/plain' : (file.type || 'application/octet-stream');

    if (this.check_file_size(file.size)) {
      this.$data.required = transferred;

      if (transferred) {
        this.data_reader.readAsDataURL(file);
        this.$file.value = '';
        this.$filename.value = file.name.replace(/\s/g, '-');
      } else {
        this.$data.value = this.$filename.value = '';
      }
    } else {
      this.$data.required = true;
      this.$file.value = this.$data.value = this.$filename.value = '';
    }

    this.update_validation();
    this.show_preview(file, file.type.startsWith('text/') || is_patch || is_text);
    this.update_text();
    this.update_content_type(type);
    this.update_ispatch(is_patch);

    if (!this.description_override) {
      this.$description.value = file.name;
    }

    this.$textarea.hidden = true;
    this.$description.select();
    this.$description.focus();
  }

  /**
   * Check the current file size and show an error message if it exceeds the application-defined limit.
   * @param {Number} size A file size in bytes.
   * @returns {Boolean} `true` if the file is less than the maximum allowed size, `false` otherwise.
   */
  check_file_size(size) {
    const file_size = size / 1024; // Convert to KB
    const max_size = BUGZILLA.param.maxattachmentsize; // Defined in KB
    const invalid = file_size > max_size;
    const message = invalid ?
      `This file (<strong>${(file_size / 1024).toFixed(1)} MB</strong>) is larger than the maximum allowed size ` +
      `(<strong>${(max_size / 1024).toFixed(1)} MB</strong>). Please consider uploading it to an online file storage ` +
      'and sharing the link in a bug comment instead.' : '';
    const message_short = invalid ? 'File too large' : '';

    this.$error_message.innerHTML = message;
    this.$data.setCustomValidity(message_short);
    this.$data.setAttribute('aria-invalid', invalid);
    this.$dropbox.classList.toggle('invalid', invalid);

    return !invalid;
  }

  /**
   * Called whenever a file's data URL is read by `FileReader`. Embed the Base64-encoded content for upload.
   */
  data_reader_onload() {
    this.$data.value = this.data_reader.result.split(',')[1];
    this.update_validation();
  }

  /**
   * Called whenever a file's text content is read by `FileReader`. Show the preview of the first 10 lines.
   */
  text_reader_onload() {
    this.$preview_text.textContent = this.text_reader.result.split(/\r\n|\r|\n/, 10).join('\n');
  }

  /**
   * Called whenever a file is selected by the user by using the file picker. Prepare for upload.
   */
  file_onchange() {
    this.process_file(this.$file.files[0], false);
  }

  /**
   * Called whenever a file is being dragged on the drop target. Allow the `copy` drop effect, and set a class name on
   * the drop target for styling.
   * @param {DragEvent} event A `dragover` event.
   */
  dropbox_ondragover(event) {
    event.preventDefault();
    event.dataTransfer.dropEffect = event.dataTransfer.effectAllowed = 'copy';

    if (!this.$dropbox.classList.contains('dragover')) {
      this.$dropbox.classList.add('dragover');
    }
  }

  /**
   * Called whenever a dragged file leaves the drop target. Reset the styling.
   */
  dropbox_ondragleave() {
    this.$dropbox.classList.remove('dragover');
  }

  /**
   * Called whenever a drag operation is being ended. Reset the styling.
   */
  dropbox_ondragend() {
    this.$dropbox.classList.remove('dragover');
  }

  /**
   * Called whenever a file or text is dropped on the drop target. If it's a file, read the content. If it's plaintext,
   * fill in the textarea.
   * @param {DragEvent} event A `drop` event.
   */
  dropbox_ondrop(event) {
    event.preventDefault();

    const files = event.dataTransfer.files;
    const text = event.dataTransfer.getData('text');

    if (files.length > 0) {
      this.process_file(files[0]);
    } else if (text) {
      this.clear_preview();
      this.clear_error();
      this.update_text(text);
    }

    this.$dropbox.classList.remove('dragover');
  }

  /**
   * Insert text to the textarea, and show it if it's not empty.
   * @param {String} [text=''] Text to be inserted.
   */
  update_text(text = '') {
    this.$textarea.value = text;
    this.textarea_oninput();

    if (text) {
      this.$textarea.hidden = false;
    }
  }

  /**
   * Called whenever the content of the textarea is updated. Update the Content Type, `required` property, etc.
   */
  textarea_oninput() {
    const text = this.$textarea.value.trim();
    const has_text = !!text;
    const is_patch = !!text.match(/^(?:diff|---)\s/);
    const is_ghpr = !!text.match(/^https:\/\/github\.com\/[\w\-]+\/[\w\-]+\/pull\/\d+\/?$/);

    if (has_text) {
      this.$file.value = this.$data.value = this.$filename.value = '';
      this.update_content_type('text/plain');
    }

    if (!this.description_override) {
      this.$description.value = is_patch ? 'patch' : is_ghpr ? 'GitHub Pull Request' : '';
    }

    this.$data.required = !has_text && !this.$file.value;
    this.update_validation();
    this.$type_input.value = is_ghpr ? 'text/x-github-pull-request' : '';
    this.update_ispatch(is_patch);
    this.$type_outer.querySelectorAll('[name]').forEach($input => $input.disabled = has_text);
  }

  /**
   * Called whenever a string or data is pasted from clipboard to the textarea. If it contains a regular image, read the
   * content for upload.
   * @param {ClipboardEvent} event A `paste` event.
   */
  textarea_onpaste(event) {
    const image = [...event.clipboardData.items].find(item => item.type.match(/^image\/(?!vnd)/));

    if (image) {
      this.process_file(image.getAsFile());
      this.update_ispatch(false, true);
    }
  }

  /**
   * Show the preview of a user-selected file. Display a thumbnail if it's a regular image (PNG, GIF, JPEG, etc.) or
   * small plaintext file.
   * @param {File} file A file to be previewed.
   * @param {Boolean} [is_text=false] `true` if the file is a plaintext file, `false` otherwise.
   */
  show_preview(file, is_text = false) {
    this.$preview_name.textContent = file.name;
    this.$preview_type.content = file.type;
    this.$preview_text.textContent = '';
    this.$preview_image.src = file.type.match(/^image\/(?!vnd)/) ? URL.createObjectURL(file) : '';
    this.$preview.hidden = false;

    if (is_text && file.size < 500000) {
      this.text_reader.readAsText(file);
    }
  }

  /**
   * Remove the preview.
   */
  clear_preview() {
    URL.revokeObjectURL(this.$preview_image.src);

    this.$preview_name.textContent = this.$preview_type.content = '';
    this.$preview_text.textContent = this.$preview_image.src = '';
    this.$preview.hidden = true;
  }

  /**
   * Called whenever the Remove buttons is clicked by the user. Reset all the fields and focus the textarea for further
   * input.
   */
  remove_button_onclick() {
    this.reset_fields();

    this.$textarea.hidden = false;
    this.$textarea.focus();
  }

  /**
   * Remove the error message if any.
   */
  clear_error() {
    this.check_file_size(0);
  }

  /**
   * Called whenever the Description is updated. Update the Patch checkbox when needed.
   */
  description_oninput() {
    if (this.$description.value.match(/\bpatch\b/i) && !this.$ispatch.checked) {
      this.update_ispatch(true);
    }
  }

  /**
   * Called whenever the Description is changed manually. Set the override flag so the user-defined Description will be
   * retained later on.
   */
  description_onchange() {
    this.description_override = true;
  }

  /**
   * Select a Content Type from the list or fill in the "enter manually" field if the option is not available.
   * @param {String} type A detected MIME type.
   */
  update_content_type(type) {
    if ([...this.$type_select.options].find($option => $option.value === type)) {
      this.$type_list.checked = true;
      this.$type_select.value = type;
      this.$type_input.value = '';
    } else {
      this.$type_manual.checked = true;
      this.$type_input.value = type;
    }
  }

  /**
   * Update the Patch checkbox state.
   * @param {Boolean} [checked=false] The `checked` property of the checkbox.
   * @param {Boolean} [disabled=false] The `disabled` property of the checkbox.
   */
  update_ispatch(checked = false, disabled = false) {
    this.$ispatch.checked = checked;
    this.$ispatch.disabled = disabled;
    this.ispatch_onchange();
  }

  /**
   * Called whenever the Patch checkbox is checked or unchecked. Disable or enable the Content Type fields accordingly.
   */
  ispatch_onchange() {
    const is_patch = this.$ispatch.checked;
    const is_ghpr = this.$type_input.value === 'text/x-github-pull-request';

    this.$type_outer.querySelectorAll('[name]').forEach($input => $input.disabled = is_patch);

    if (is_patch) {
      this.update_content_type('text/plain');
    }

    // Reassign the bug to the user if the attachment is a patch or GitHub Pull Request
    if (this.$takebug && this.$takebug.clientHeight > 0 && this.$takebug.dataset.takeIfPatch) {
      this.$takebug.checked = is_patch || is_ghpr;
    }
  }

  /**
   * Called whenever an option is selected from the Content Type list. Select the "select from list" radio button.
   */
  type_select_onchange() {
    this.$type_list.checked = true;
  }

  /**
   * Called whenever the used manually specified the Content Type. Select the "select from list" or "enter manually"
   * radio button depending on the value.
   */
  type_input_onchange() {
    if (this.$type_input.value) {
      this.$type_manual.checked = true;
    } else {
      this.$type_list.checked = this.$type_select.options[0].selected = true;
    }
  }
};

window.addEventListener('DOMContentLoaded', () => bz_attachment_form = new Bugzilla.AttachmentForm(), { once: true });
