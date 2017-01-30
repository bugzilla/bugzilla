/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

$(function() {
    'use strict';
    var dayMs = 24 * 60 * 60 * 1000;
    var limit = 7;

    function getOrangeCount(data) {
        data = data.oranges;
        var total = 0,
            days = [],
            date = getCurrentDateMs() - limit * dayMs;
        for(var i = 0; i < limit; i++) {
            var iso = dateString(new Date(date));
            var count = data[iso] ? data[iso].orangecount : 0;
            days.push(count);
            total += count;
            date += dayMs;
        }
        displayGraph(days);
        displayCount(total);
    }

    function displayGraph(dayCounts) {
        var max = dayCounts.reduce(function(max, count) {
            return count > max ? count : max;
        });
        $('#orange-graph')
            .attr('title', 'failures over the past week, max in a day: ' + max)
            .show();
        var  opts = {
            "percentage_lines":[0.25, 0.5, 0.75],
            "fill_between_percentage_lines": false,
            "left_padding": 0,
            "right_padding": 0,
            "top_padding": 0,
            "bottom_padding": 0,
            "background": "#D0D0D0",
            "stroke": "#000000",
            "percentage_fill_color": "#CCCCFF",
            "scale_from_zero": true,
        };
        new Sparkline('orange-graph', dayCounts, opts).draw();
    }

    function displayCount(count) {
        $('#orange-count').text(count + ' failures on trunk in the past week');
    }

    function dateString(date) {
        function norm(part) {
            return JSON.stringify(part).length == 2 ? part : '0' + part;
        }
        return date.getFullYear()
            + "-" + norm(date.getMonth() + 1)
            + "-" + norm(date.getDate());
    }

    function getCurrentDateMs() {
        var d = new Date;
        return d.getTime();
    };

    function orangify() {
        $('#orange-count')
            .text('Loading...')
            .show();
        var bugId = document.forms['changeform'].id.value;
        var request = {
            dataType: "json",
            url: "https://brasstacks.mozilla.com/orangefactor/api/count?" +
                 "bugid=" + encodeURIComponent(bugId) + "&tree=trunk"
        };
        $.ajax(request)
            .done(function(data) {
                getOrangeCount(data);
            })
            .fail(function() {
                $('#graph-count').hide();
                $('#orange-graph').hide()
            });
    }

    orangify();
});
