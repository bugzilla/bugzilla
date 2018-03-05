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
        this.initialized = false;
        this.$button = document.querySelector('#header-requests-menu-button');
        this.$panel = document.querySelector('#header-requests .dropdown-panel');
        this.$loading = document.querySelector('#header-requests .dropdown-panel .loading');

        if (this.$loading) {
            this.$button.addEventListener('mouseover', () => this.init(), { once: true });
            this.$button.addEventListener('focus', () => this.init(), { once: true });
        }
    }

    /**
     * Initialize the Reviews dropdown menu.
     */
    async init() {
        if (this.initialized) {
            return;
        }

        this.initialized = true;

        const url = this.$panel.querySelector('footer a').href.replace(/type$/, 'requestee') + '&ctype=json';
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
            const dup_index = requests.findIndex(req => req.requester === _req.requester && req.type === _req.type
                && req.bug_id === _req.bug_id && req.attach_mimetype === _req.attach_mimetype);

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
            const [, name, email] = req.requester.match(/^(?:(.*)\s<)?(.+?)>?$/);
            const pretty_name = name ? name.replace(/([\[\(<‹].*?[›>\)\]]|\:[\w\-]+|\s+\-\s+.*)/g, '').trim() : email;
            const [link, attach_label] = this.get_link(req);

            $li.setAttribute('role', 'none');
            $li.innerHTML = `<a href="${link.htmlEncode()}" role="menuitem" tabindex="-1" `
                + `class="${(req.restricted ? 'secure' : '')}" data-type="${req.type}">`
                + `<img src="https://secure.gravatar.com/avatar/${md5(email.toLowerCase())}?d=mm&amp;size=64" alt="">`
                + `<label><strong>${pretty_name.htmlEncode()}</strong> asked for your `
                + (req.type === 'needinfo' ? 'info' : req.type) + (attach_label ? ` on ${attach_label}` : '')
                + ' in ' + (req.restricted ? '<span class="icon" aria-label="secure"></span>&nbsp;' : '')
                + `<strong>Bug ${req.bug_id} &ndash; ${req.bug_summary.htmlEncode()}</strong>.</label>`
                + `<time datetime="${req.created}">${timeAgo(new Date(req.created))}</time></a>`;
            $fragment.appendChild($li);
        });

        this.$loading.remove();
        $ul.appendChild($fragment);
        $ul.hidden = false;
    }

    /**
     * Get the link to a request as well as the label of any attachment. It could be the direct link to the attachment
     * unless multiple requests are grouped.
     * @param {Object} req - A request object.
     * @returns {Array<String>} The result including the link and attachment label.
     */
    get_link(req) {
        const dup = req.dup_count > 1;
        const splinter_base = BUGZILLA.param.splinter_base;
        const x_types = ['github-pull-request', 'review-board-request', 'phabricator-request', 'google-doc'];
        const is_patch = req.attach_ispatch;
        const [is_ghpr, is_rbr, is_phr, is_gdoc] = x_types.map(type => req.attach_mimetype === `text/x-${type}`);
        const is_redirect = is_ghpr || is_rbr || is_phr || is_gdoc;
        const is_file = req.attach_id && !is_patch && !is_redirect;

        const link = (is_patch && !dup && splinter_base)
            ? `${splinter_base}&bug=${req.bug_id}&attachment=${req.attach_id}`
            : (is_redirect && !dup) ? `attachment.cgi?id=${req.attach_id}` // external redirect
                : ((is_patch || is_file) && !dup) ? `attachment.cgi?id=${req.attach_id}&action=edit`
                    : `show_bug.cgi?id=${req.bug_id}`;

        const attach_label = (is_patch || is_rbr || is_phr) ? (dup ? `${req.dup_count} patches` : 'a patch')
            : is_ghpr ? (dup ? `${req.dup_count} pull requests` : 'a pull request')
                : is_gdoc ? (dup ? `${req.dup_count} Google Docs` : 'a Google Doc')
                    : is_file ? (dup ? `${req.dup_count} files` : 'a file')
                        : undefined;

        return [link, attach_label];
    }
}

window.addEventListener('DOMContentLoaded', () => new Bugzilla.Review.Badge(), { once: true });
