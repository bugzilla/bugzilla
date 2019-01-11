/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

var Phabricator = {};

Phabricator.getBugRevisions = function() {
    var phabUrl = $('.phabricator-revisions').data('phabricator-base-uri');
    var tr      = $('<tr/>');
    var td      = $('<td/>');
    var link    = $('<a/>');
    var span    = $('<span/>');
    var table   = $('<table/>');

    function revisionRow(revision) {
        var trRevision     = tr.clone();
        var tdId           = td.clone();
        var tdTitle        = td.clone();
        var tdAuthor       = td.clone();
        var tdRevisionStatus       = td.clone();
        var tdReviewers    = td.clone();
        var tableReviews   = table.clone();

        var spanRevisionStatus     = span.clone();
        var spanRevisionStatusIcon = span.clone();
        var spanRevisionStatusText = span.clone();

        var revLink = link.clone();
        revLink.attr('href', phabUrl + '/' + revision.id);
        revLink.text(revision.id);
        tdId.append(revLink);

        tdTitle.text(revision.title);
        tdTitle.addClass('phabricator-title');

        tdAuthor.text(revision.author);

        spanRevisionStatusIcon.addClass('revision-status-icon-' + revision.status);
        spanRevisionStatus.append(spanRevisionStatusIcon);
        spanRevisionStatusText.text(revision.long_status);
        spanRevisionStatus.append(spanRevisionStatusText);
        spanRevisionStatus.addClass('revision-status-box-' + revision.status);
        tdRevisionStatus.append(spanRevisionStatus);

        var i = 0, l = revision.reviews.length;
        for (; i < l; i++) {
            var trReview             = tr.clone();
            var tdReviewStatus       = td.clone();
            var tdReviewer           = td.clone();
            var spanReviewStatusIcon = span.clone();
            trReview.prop('title', revision.reviews[i].long_status);
            spanReviewStatusIcon.addClass('review-status-icon-' + revision.reviews[i].status);
            tdReviewStatus.append(spanReviewStatusIcon);
            tdReviewer.text(revision.reviews[i].user);
            tdReviewer.addClass('review-reviewer');
            trReview.append(tdReviewStatus, tdReviewer);
            tableReviews.append(trReview);
        }
        tableReviews.addClass('phabricator-reviewers');
        tdReviewers.append(tableReviews);

        trRevision.attr('data-status', revision.status);
        if (revision.status === 'abandoned') {
            trRevision.addClass('bz_default_hidden');
            $('tbody.phabricator-show-abandoned').removeClass('bz_default_hidden');
        }

        trRevision.append(
            tdId,
            tdTitle,
            tdAuthor,
            tdRevisionStatus,
            tdReviewers
        );

        return trRevision;
    }

    var tbody = $('tbody.phabricator-revision');

    function displayLoadError(errStr) {
        var errRow = tbody.find('.phabricator-loading-error-row');
        errRow.find('.phabricator-load-error-string').text(errStr);
        errRow.removeClass('bz_default_hidden');
    }

    var $getUrl = '/rest/phabbugz/bug_revisions/' + BUGZILLA.bug_id +
                  '?Bugzilla_api_token=' + BUGZILLA.api_token;

    $.getJSON($getUrl, function(data) {
        if (data.revisions.length === 0) {
            displayLoadError('none returned from server');
        } else {
            var i = 0;
            for (; i < data.revisions.length; i++) {
                tbody.append(revisionRow(data.revisions[i]));
            }
        }
        tbody.find('.phabricator-loading-row').addClass('bz_default_hidden');
    }).fail(function(jqXHR, textStatus, errorThrown) {
        var errStr;
        if (jqXHR.responseJSON && jqXHR.responseJSON.err &&
            jqXHR.responseJSON.err.msg) {
            errStr = jqXHR.responseJSON.err.msg;
        } else if (errorThrown) {
            errStr = errorThrown;
        } else {
            errStr = 'unknown';
        }
        displayLoadError(errStr);
        tbody.find('.phabricator-loading-row').addClass('bz_default_hidden');
    });
};

$().ready(function() {
    Phabricator.getBugRevisions();

    $('#phabricator-show-abandoned').on('click', function (event) {
        $('tbody.phabricator-revision > tr').each(function() {
            var row = $(this);
            if (row.attr('data-status') === 'abandoned') {
                if ($('#phabricator-show-abandoned').prop('checked') == true) {
                    row.removeClass('bz_default_hidden');
                }
                else {
                    row.addClass('bz_default_hidden');
                }
            }
        });
    });
});
