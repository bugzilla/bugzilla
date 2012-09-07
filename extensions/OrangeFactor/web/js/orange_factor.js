/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

YAHOO.namespace('OrangeFactor');

var OrangeFactor = YAHOO.OrangeFactor;

OrangeFactor.dayMs = 24 * 60 * 60 * 1000,
OrangeFactor.limit = 7;

OrangeFactor.getOrangeCount = function (data) {
    data = data.oranges;
    var total = 0,
        days = [],
        date = OrangeFactor.getCurrentDateMs() - OrangeFactor.limit * OrangeFactor.dayMs;
    for(var i = 0; i < OrangeFactor.limit; i++) {
        var iso = OrangeFactor.dateString(new Date(date));
        var count = data[iso] ? data[iso].orangecount : 0;
        days.push(count);
        total += count;
        date += OrangeFactor.dayMs;
    }
    OrangeFactor.displayGraph(days);
    OrangeFactor.displayCount(total);
}

OrangeFactor.displayGraph = function (dayCounts) {
    var max = dayCounts.reduce(function(max, count) {
        return count > max ? count : max;
    });
    var graphContainer = YAHOO.util.Dom.get('orange-graph');
    Dom.removeClass(graphContainer, 'bz_default_hidden');
    YAHOO.util.Dom.setAttribute(graphContainer, 'title',
                                'failures over the past week, max in a day: ' + max);
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

OrangeFactor.displayCount = function (count) {
    var countContainer = YAHOO.util.Dom.get('orange-count');
    countContainer.innerHTML = encodeURIComponent(count) + ' failures in the past week';
}

OrangeFactor.dateString = function (date) {
    function norm(part) {
        return JSON.stringify(part).length == 2 ? part : '0' + part;
    }
    return date.getFullYear()
           + "-" + norm(date.getMonth() + 1)
           + "-" + norm(date.getDate());
}

OrangeFactor.getCurrentDateMs = function () {
    var d = new Date;
    return d.getTime();
}

OrangeFactor.orangify = function () {
    var bugId = document.forms['changeform'].id.value;
    var url = "https://brasstacks.mozilla.com/orangefactor/api/count?" +
              "bugid=" + encodeURIComponent(bugId) +
              "&callback=OrangeFactor.getOrangeCount";
    var script = document.createElement('script');
    Dom.setAttribute(script, 'src', url);
    Dom.setAttribute(script, 'type', 'text/javascript');
    var head = document.getElementsByTagName('head')[0];
    head.appendChild(script);
    var countContainer = YAHOO.util.Dom.get('orange-count');
    Dom.removeClass(countContainer, 'bz_default_hidden');
    countContainer.innerHTML = 'Loading...';a
}

YAHOO.util.Event.onDOMReady(OrangeFactor.orangify);
