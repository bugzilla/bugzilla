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
    var hostUrl = $('.mozreview-table').data('mozreviewUrl');
    var tr = $('<tr/>');
    var td = $('<td/>');

    var rrApiBaseUrl = hostUrl +
            'api/extensions/mozreview.extension.MozReviewExtension/summary/';
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

    $('.mozreview-hide-discarded-link').click(function() {
        if ($('.bz_default_hidden.mozreview-discarded-request').length) {
            $('.mozreview-discarded-request').removeClass('bz_default_hidden');
            $('.mozreview-discarded-action').text('Hide');
        } else {
            $('.mozreview-discarded-request').addClass('bz_default_hidden');
            $('.mozreview-discarded-action').text('Show');
        }
        return false;
    });

    $('.mozreview-request').each(function() {
        var tbody = $(this);
        var rrId = tbody.data('rrid');
        var url = rrApiBaseUrl + rrId + '/';
        var i;

        $.getJSON(url, function(data) {
            var parent = data.parent;
            tbody.append(rrRow(parent, true));
            for (i = 0; i < data.children.length; i++) {
                tbody.append(rrRow(data.children[i], false));
            }
            tbody.find('.mozreview-loading-row').addClass('bz_default_hidden');
        }).fail(function(jqXHR, textStatus, errorThrown) {
            tbody.find('.mozreview-loading-row').addClass('bz_default_hidden');
            tbody.find('.mozreview-load-error-rrid').text(rrId);
            var errRow = tbody.find('.mozreview-loading-error-row');
            var errStr;
            if (jqXHR.responseJSON && jqXHR.responseJSON.err &&
                jqXHR.responseJSON.err.msg) {
                errStr = jqXHR.responseJSON.err.msg;
            } else if (errorThrown) {
                errStr = errorThrown;
            } else {
                errStr = 'unknown';
            }
            errRow.find('.mozreview-load-error-string').text(errStr);
            errRow.removeClass('bz_default_hidden');
        });
    });
};

$().ready(function() {
    MozReview.getReviewRequest();
});
