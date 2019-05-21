/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

/**
 * Activate a Dependency Tree so the user can expand/collapse trees and highlight duplicates.
 */
Bugzilla.DependencyTree = class DependencyTree {
  /**
   * Initialize a new DependencyTree instance.
   * @param {HTMLUListElement} $tree The topmost element of a tree.
   */
  constructor($tree) {
    $tree.querySelectorAll('.expander').forEach($button => {
      $button.addEventListener('click', event => this.toggle_treeitem(event));
    });

    $tree.querySelectorAll('.duplicate-highlighter').forEach($button => {
      $button.addEventListener('click', event => this.highlight_duplicates(event));
    });

    $tree.querySelectorAll('.summary.duplicated .bug-link').forEach($link => {
      $link.addEventListener('mouseenter', event => this.highlight_duplicates(event));
      $link.addEventListener('mouseleave', event => this.highlight_duplicates(event));
    });
  }

  /**
   * Expand or collapse one or more tree items.
   * @param {MouseEvent} event `click` event.
   */
  toggle_treeitem(event) {
    const { target, altKey, ctrlKey, metaKey, shiftKey } = event;
    const $item = target.closest('[role="treeitem"]');
    const expanded = $item.matches('[aria-expanded="false"]');
    const accelKey = navigator.platform === 'MacIntel' ? metaKey && !ctrlKey : ctrlKey;

    $item.setAttribute('aria-expanded', expanded);

    // Do the same for the subtrees if the Ctrl/Command key is pressed
    if (accelKey && !altKey && !shiftKey) {
      $item.querySelectorAll('[role="treeitem"]').forEach($child => {
        $child.setAttribute('aria-expanded', expanded);
      });
    }
  }

  /**
   * Highlight one or more duplicated tree items.
   * @param {MouseEvent} event `click`, `mouseenter` or `mouseleave` event.
   */
  highlight_duplicates(event) {
    const { target, type } = event;
    const id = Number(target.closest('[role="treeitem"]').dataset.id);
    const pressed = type === 'click' ? target.matches('[aria-pressed="false"]') : undefined;

    if (type.startsWith('mouse') && this.highlighted) {
      return;
    }

    if (type === 'click') {
      if (this.highlighted) {
        // Remove existing highlights
        document.querySelectorAll(`[role="treeitem"][data-id="${this.highlighted}"]`).forEach($item => {
          const $highlighter = $item.querySelector('.duplicate-highlighter');

          if ($highlighter) {
            $highlighter.setAttribute('aria-pressed', 'false');
          }

          $item.querySelector('.summary').classList.remove('highlight');
        });
      }

      target.setAttribute('aria-pressed', pressed);
      this.highlighted = pressed ? id : undefined;
    }

    document.querySelectorAll(`[role="treeitem"][data-id="${id}"]`).forEach(($item, index) => {
      $item.querySelector('.summary').classList.toggle('highlight', pressed);

      if (index === 0 && pressed) {
        $item.scrollIntoView();
      }
    });
  }
};

window.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[role="tree"]').forEach($tree => {
    new Bugzilla.DependencyTree($tree);
  });
}, { once: true });
