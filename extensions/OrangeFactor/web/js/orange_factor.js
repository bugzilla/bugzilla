/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

$(function() {
    'use strict';

    function getOrangeCount(data) {
        let days = [];
        let total = 0;

        data.forEach(entry => {
            let failureCount = entry["failure_count"];
            days.push(failureCount);
            total += failureCount;
        });

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

    function orangify() {
        let $orangeCount = $('#orange-count');
        let queryParams = $.param({
            bug: $orangeCount.data('bug-id'),
            startday: $orangeCount.data('date-start'),
            endday: $orangeCount.data('date-end'),
            tree: 'trunk'
        });
        let request = {
            dataType: "json",
            url: `https://treeherder.mozilla.org/api/failurecount/?${queryParams}`
        };

        $orangeCount.text('Loading...').show();
        $.ajax(request)
            .done(function(data) {
                getOrangeCount(data);
            })
            .fail(function() {
                $orangeCount.text('Unable to load OrangeFactor at this time.');
            });
    }

    orangify();
});
