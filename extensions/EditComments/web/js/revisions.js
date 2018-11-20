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
 * Allow admin to hide specific comment revisions from public, in case any of these contains sensitive info.
 */
Bugzilla.CommentRevisionsManager = class CommentRevisionsManager {
  /**
   * Initialize a new CommentRevisionsManager instance.
   */
  constructor() {
    document.querySelectorAll('.revision').forEach($revision => this.activate($revision));
  }

  /**
   * Activate the "Hide" checkbox on each revision so the change triggers an immediate update to the database.
   * @param {HTMLElement} $revision Revision container node.
   */
  activate($revision) {
    const $checkbox = $revision.querySelector('input[name="is_hidden"]');

    // The current revision cannot be hidden so there is no checkbox on it
    if (!$checkbox) {
      return;
    }

    const comment_id = Number($revision.dataset.commentId);
    const change_when = $revision.dataset.revisedTime;

    $checkbox.addEventListener('change', () => {
      bugzilla_ajax({
        url: `${BUGZILLA.config.basepath}rest/editcomments/revision`,
        type: 'PUT',
        data: {
          comment_id,
          change_when,
          is_hidden: $checkbox.checked ? 1 : 0,
        },
      });
    });
  }
};

window.addEventListener('DOMContentLoaded', () => new Bugzilla.CommentRevisionsManager());
