/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0.
 */

var MozReview = {};

MozReview.formatElapsedTime = function(s, val) {
    val = Math.floor(val);
    return val + ' ' + s + (val == 1 ? '' : 's') + ' ago';
};

MozReview.elapsedTime = function(d) {
    var ms = Date.now() - d;

    var seconds = ms / 1000;
    if (seconds < 60) {
        return MozReview.formatElapsedTime('second', seconds);
    }

    var minutes = seconds / 60;
    if (minutes < 60) {
        return MozReview.formatElapsedTime('minute', minutes);
    }

    var hours = minutes / 60;
    if (hours < 24) {
        return MozReview.formatElapsedTime('hour', hours);
    }

    var days = hours / 24;
    if (days < 30) {
        return MozReview.formatElapsedTime("day", days);
    }

    var months = days / 30;  // enh fudge it
    if (months < 12) {
        return MozReview.formatElapsedTime("month", months);
    }

    var years = months / 12;
    return MozReview.formatElapsedTime("year", years);
};

MozReview.getReviewRequest = function() {
    var hostUrl = $('.mozreview-requests').data('mozreviewUrl');
    var tr = $('<tr/>');
    var td = $('<td/>');

    var rrSummaryApiUrl = hostUrl +
        'api/extensions/mozreview.extension.MozReviewExtension/summary/?bug=' +
        BUGZILLA.bug_id;
    var rrUiBaseUrl = hostUrl + 'r/';

    function rrUrl(rrId) {
        return rrUiBaseUrl + rrId + '/';
    }

    function rrRow(rr, isParent) {
        var tdSummary = td.clone();
        var trCommit = tr.clone();
        var a = $('<a/>');

        if (!isParent) {
            tdSummary.addClass('mozreview-child-request-summary');
        }

        a.attr('href', rrUrl(rr.id));
        a.text(rr.summary);
        tdSummary.append(a);

        if (isParent) {
            tdSummary.append($('<span/>').text(' (' + rr.submitter + ')'));
        }

        tdSummary.addClass('mozreview-summary');

        trCommit.append(
            tdSummary,
            td.clone().text(rr.status),
            td.clone().text(rr.issue_open_count)
                      .addClass('mozreview-open-issues'),
            td.clone().text(MozReview.elapsedTime(new Date(rr.last_updated)))
        );

        if (rr.status == "discarded") {
            $('.mozreview-hide-discarded-row').removeClass('bz_default_hidden');
            trCommit.addClass('bz_default_hidden mozreview-discarded-request');
        }

        return trCommit;
    }

    $('.mozreview-hide-discarded-link').click(function(event) {
        event.preventDefault();
        if ($('.bz_default_hidden.mozreview-discarded-request').length) {
            $('.mozreview-discarded-request').removeClass('bz_default_hidden');
            $('.mozreview-discarded-action').text('Hide');
        } else {
            $('.mozreview-discarded-request').addClass('bz_default_hidden');
            $('.mozreview-discarded-action').text('Show');
        }
    });

    var tbody = $('tbody.mozreview-request');

    function displayLoadError(errStr) {
        var errRow = tbody.find('.mozreview-loading-error-row');
        errRow.find('.mozreview-load-error-string').text(errStr);
        errRow.removeClass('bz_default_hidden');
    }

    $.getJSON(rrSummaryApiUrl, function(data) {
        var family, parent, i, j;

        if (data.review_request_summaries.length === 0) {
            displayLoadError('none returned from server');
        } else {
            for (i = 0; i < data.review_request_summaries.length; i++) {
                family = data.review_request_summaries[i];
                parent = family.parent;
                tbody.append(rrRow(parent, true));
                for (j = 0; j < family.children.length; j++) {
                    tbody.append(rrRow(family.children[j], false));
                }
            }
        }

        tbody.find('.mozreview-loading-row').addClass('bz_default_hidden');
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
        tbody.find('.mozreview-loading-row').addClass('bz_default_hidden');
    });
};

$().ready(function() {
    MozReview.getReviewRequest();
});
