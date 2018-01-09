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
var Bugzilla = Bugzilla || {};

/**
 * Reference or define the Review namespace.
 * @namespace
 */
Bugzilla.Review = Bugzilla.Review || {};

/**
 * Provide the Badge functionality that shows the current review summary in the dropdown.
 */
Bugzilla.Review.Badge = class Badge {
    /**
     * Get a new Badge instance.
     * @returns {Badge} New Badge instance.
     */
    constructor() {
        this.$button = document.querySelector('#header-requests-menu-button');
        this.$panel = document.querySelector('#header-requests .dropdown-panel');
        this.$loading = document.querySelector('#header-requests .dropdown-panel .loading');

        if (this.$loading) {
            this.$button.addEventListener('click', () => this.init(), { once: true });
        }
    }

    /**
     * Initialize the Reviews dropdown menu.
     */
    async init() {
        const url = this.$panel.querySelector('footer a').href + '&ctype=json';
        const response = await fetch(url, { credentials: 'same-origin' });
        const _requests = response.ok ? await response.json() : [];

        if (!response.ok) {
            this.$loading.innerHTML = 'Couldn’t load requests for you.<br>Please try again later.';

            return;
        }

        if (!_requests.length) {
            this.$loading.className = 'empty';
            this.$loading.innerHTML = 'You’re all caught up!';

            return;
        }

        const requests = [];
        const $ul = this.$panel.querySelector('ul');
        const $fragment = document.createDocumentFragment();

        // Sort requests from new to old, then group reviews/feedbacks asked by the same person in the same bug
        _requests.reverse().forEach(_req => {
            const dup_index = requests.findIndex(req => req.requester === _req.requester
                && req.bug_id === _req.bug_id && req.type === _req.type && req.attach_id && _req.attach_id);

            if (dup_index > -1) {
                requests[dup_index].dup_count++;
            } else {
                _req.dup_count = 1;
                requests.push(_req);
            }
        });

        // Show up to 20 newest requests
        requests.slice(0, 20).forEach(req => {
            const $li = document.createElement('li');
            const [, name, email] = req.requester.match(/^(.*)\s<(.*)>$/);
            const pretty_name = name.replace(/([\[\(<‹].*?[›>\)\]]|\:[\w\-]+|\s+\-\s+.*)/g, '').trim();
            const link = req.attach_id && req.dup_count === 1
                ? `attachment.cgi?id=${req.attach_id}&amp;action=edit` : `show_bug.cgi?id=${req.bug_id}`;

            $li.setAttribute('role', 'none');
            $li.innerHTML = `<a href="${link}" role="menuitem" tabindex="-1" `
                + `class="${(req.restricted ? 'secure' : '')}" data-type="${req.type}">`
                + `<img src="https://secure.gravatar.com/avatar/${md5(email)}?d=mm&amp;size=64" alt="">`
                + `<label><strong>${pretty_name.htmlEncode()}</strong> asked for your `
                + (req.type === 'needinfo' ? 'info' : req.type) + (req.attach_id ? ' on ' : '')
                + (req.attach_id && req.ispatch ? (req.dup_count > 1 ? `${req.dup_count} patches` : 'a patch') : '')
                + (req.attach_id && !req.ispatch ? (req.dup_count > 1 ? `${req.dup_count} files` : 'a file') : '')
                + ' in ' + (req.restricted ? '<span class="icon" aria-label="secure"></span>&nbsp;' : '')
                + `<strong>Bug ${req.bug_id} &ndash; ${req.bug_summary.htmlEncode()}</strong>.</label>`
                + `<time datetime="${req.created}">${timeAgo(new Date(req.created))}</time></a>`;
            $fragment.appendChild($li);
        });

        this.$loading.remove();
        $ul.appendChild($fragment);
        $ul.hidden = false;
    }
}

window.addEventListener('DOMContentLoaded', () => new Bugzilla.Review.Badge(), { once: true });
