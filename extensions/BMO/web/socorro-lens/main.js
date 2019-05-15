var theme = 'dark';

(function () {
  'use strict';

  //set the active pill and section on first load
  var section = (document.location.hash) ? document.location.hash.slice(1) : 'signature_lookup';

  if (section.indexOf("bugzilla") != -1) {
    $('#trunk').load('charts/bugzilla/' + section + '.htm', function () {
      $('pre code').each(function (i, block) {
        hljs.highlightBlock(block);
      });
    });
  } else {
    if (section.indexOf("bz_signatures") != -1) {
      $('#trunk').load('charts/bz_signatures.htm', function () {
        $('pre code').each(function (i, block) {
          hljs.highlightBlock(block);
        });
      });
    } else {
      $('#trunk').load('charts/' + section + '.htm', function () {
        $('pre code').each(function (i, block) {
          hljs.highlightBlock(block);
        });
      });
    }
  }

  $('.menu a#goto-' + section).addClass('active');

  //handle mouse clicks and so on
  assignEventListeners();

  function assignEventListeners() {
    $('button.load').on('click', function (event) {
      var metric = document.getElementById('select_metric').selectedOptions[0].value;
      if (metric.indexOf('bugzilla') != -1) {
        metric = 'bugzilla/' + metric;
      }
      var chart = 'charts/' + metric + '.htm';
      $('#trunk').load(chart, function () {
        $('pre code').each(function (i, block) {
          hljs.highlightBlock(block);
        });
      });
    })

    $('a.pill').on('click', function (event) {
      event.preventDefault();
      $('a.pill').removeClass('active');
      $(this).addClass('active');

      var section = $(this).attr('id').slice(5);
      if (section.indexOf("bugzilla") != -1) {
        $('#trunk').load('charts/bugzilla/' + section + '.htm', function () {
          $('pre code').each(function (i, block) {
            hljs.highlightBlock(block);
          });
        });
      } else {
        $('#trunk').load('charts/' + section + '.htm', function () {
          $('pre code').each(function (i, block) {
            hljs.highlightBlock(block);
          });
        });
      }

      document.location.hash = section;

      return false;
    })

    $('#dark-css').on('click', function () {
      theme = 'dark';

      $('.missing')
        .css('background-image', 'url(images/missing-data-dark.png)');

      $('.wip')
        .css('background-color', '#3b3b3b');

      $('.trunk-section')
        .css('border-top-color', '#5e5e5e');

      $('.mg-missing-background')
        .css('stroke', '#ccc');

      $('.head ul li a.pill').removeClass('active');
      $(this).toggleClass('active');
      $('#dark').attr({ href: 'css/metricsgraphics-demo-dark.css' });
      $('#dark-code').attr({ href: 'css/railscasts.css' });
      $('#accessible').attr({ href: '' });

      return false;
    });

    $('#light-css').on('click', function () {
      theme = 'light';

      $('.missing')
        .css('background-image', 'url(images/missing-data.png)');

      $('.wip')
        .css('background-color', '#f1f1f1');

      $('.trunk-section')
        .css('border-top-color', '#ccc');

      $('.mg-missing-background')
        .css('stroke', 'blue');

      $('.head ul li a.pill').removeClass('active');
      $(this).toggleClass('active');
      $('#dark').attr({ href: '' });
      $('#dark-code').attr({ href: '' });
      $('#accessible').attr({ href: '' });

      return false;
    });



    $('#accessible-css').on('click', function () {
      $('.head ul li a.pill').removeClass('active');
      $(this).toggleClass('active');
      $('#accessible').attr({ href: 'css/metricsgraphics-demo-accessible.css' });

      return false;
    });
  }

  // replace all SVG images with inline SVG
  // http://stackoverflow.com/questions/11978995/how-to-change-color-of-svg
  // -image-using-css-jquery-svg-image-replacement
  $('img.svg').each(function () {
    var $img = jQuery(this);
    var imgID = $img.attr('id');
    var imgClass = $img.attr('class');
    var imgURL = $img.attr('src');

    $.get(imgURL, function (data) {
      // Get the SVG tag, ignore the rest
      var $svg = jQuery(data).find('svg');

      // Add replaced image's ID to the new SVG
      if (typeof imgID !== 'undefined') {
        $svg = $svg.attr('id', imgID);
      }
      // Add replaced image's classes to the new SVG
      if (typeof imgClass !== 'undefined') {
        $svg = $svg.attr('class', imgClass + ' replaced-svg');
      }

      // Remove any invalid XML tags as per http://validator.w3.org
      $svg = $svg.removeAttr('xmlns:a');

      // Replace image with new SVG
      $img.replaceWith($svg);

    }, 'xml');
  });
})();

document.addEventListener('DOMContentLoaded', function () {
  document.querySelector('select[name="channel"]').onchange = channelEventHandler;
  document.querySelector('select[name="match"]').onchange = matchEventHandler;
  document.querySelector('button[name="zoom"]').onclick = zoomEventHandler;
  loadGraph(window.location.search);
}, false);

function channelEventHandler(event) {
  redraw(event.target.value);
}

function matchEventHandler(event) {
  loadGraph(window.location.search, event.target.value);
}

function zoomEventHandler(event) {
  var zoom_button = document.getElementById('zoom');
  var container = window.parent.document.getElementById('chart');

  if (event.target.textContent == '+') {
    zoom_button.innerHTML = '-';
    zoom_button.title = 'Zoom Out';
    container.style.transform = 'scale(2,2)';
  } else if (event.target.textContent == '-') {
    zoom_button.innerHTML = '+';
    zoom_button.title = 'Zoom In';
    container.style.transform = 'scale(1,1)';
  }
}

var items = [];
var end_date = convertDate(new Date((new Date()).valueOf() - 1000 * 60 * 60 * 24 * 1));
var start_date = convertDate(new Date((new Date()).valueOf() - 1000 * 60 * 60 * 24 * 180));
var globals = {
  "url_base": "https://crash-stats.mozilla.org/search/?",
  "url": [],
  "mouseover": function (d) {
    var next = new Date(d.date.valueOf() + 1 * 24 * 60 * 60 * 1000);
    d3.select('svg .mg-active-datapoint').text();
    $.each(globals.url, function (i) {
      if (globals.url[i].indexOf("&date=>%3D") !== -1) {
        globals.url[i] = globals.url[i].substring(0, globals.url[i].indexOf("&date=>%3D"));
      }
      globals.url[i] = globals.url[i] + "&date=>%3D" + convertDate(d.date) + "&date=%3C" + convertDate(next);
      globals.url[i] = globals.url[i].replace("/?&signature", "/?signature");
    });
    document.getElementById('chart').title = "Click to show reports for " + convertDate(d.date);
  }
};

function convertDate(d) {
  var day = (d.getDate() < 10) ? '0' + d.getDate().toString() : d.getDate().toString();
  var month = ((d.getMonth() + 1) < 10) ? '0' + (d.getMonth() + 1).toString() : (d.getMonth() + 1).toString();
  var year = d.getFullYear().toString();
  return year + '-' + month + '-' + day;
}

function getSignaturesFromURL(search, match) {
  search = (new URLSearchParams(search)).get('s').replace(/\s/g, '%20');
  var signatures = [];
  if (search.indexOf("\\") !== -1) {
    signatures = search.split("\\");
  } else if (search.indexOf("%5C") !== -1) {
    signatures = search.split("%5C");
  } else {
    signatures = [search];
  }
  var result = [""];
  var j = 0;
  $.each(signatures, function (i) {
    if (result[j].length > 500) result[++j] = "";
    if (signatures[i] != "") {
      if (match == "exact") {
        result[j] = result[j] + "&signature=%3D" + signatures[i]
      } else {
        result[j] = result[j] + "&signature=~" + signatures[i]
      }
    }
  });
  return result;
}

function draw() {
  var channel = document.querySelector('select[name="channel"]').selectedOptions[0].value;
  items = MG.convert.date(items, 'date');
  MG.data_graphic({
    data: items,
    width: 300,
    height: 170,
    target: document.getElementById('chart'),
    x_accessor: 'date',
    y_accessor: channel,
    yax_count: 3,
    chart_type: "line",
    mouseover: globals.mouseover
  });
  if (globals.url.length > 1) {
    var target = document.getElementById('warn');
    target.style.visibility = "visible";
    target.innerHTML = "Report will open " + globals.url.length + " tabs</p>";
  }
  var mouseouts = d3.selectAll('.mg-rollover-rect rect').on('mouseout');
  d3.selectAll('.mg-rollover-rect rect').on('click', function (d) {
    $.each(globals.url, function (i) {
      window.open(globals.url[i], '_blank');
    });
  });
}

function redraw(channel) {
  MG.data_graphic({
    data: items,
    width: 300,
    height: 170,
    target: document.getElementById('chart'),
    x_accessor: 'date',
    y_accessor: channel,
    yax_count: 3,
    chart_type: "line",
    mouseover: globals.mouseover
  });

  if (globals.url.length > 1) {
    var target = document.getElementById('warn');
    target.style.visibility = "visible";
    target.innerHTML = "[!] Report will open " + globals.url.length + " tabs due to signature length.</p>";
  }

  var mouseouts = d3.selectAll('.mg-rollover-rect rect').on('mouseout');
  d3.selectAll('.mg-rollover-rect rect').on('click', function (d) {
    $.each(globals.url, function (i) {
      window.open(globals.url[i], '_blank');
    });
  });
}

function loadGraph(search, match = 'exact') {
  // Get all signatures from the Bugzilla page
  var signatures = getSignaturesFromURL(search, match);
  // Initialize chart data
  items = [];
  for (var i = 1; i < 181; i++) {
    items.push({
      "date": convertDate(new Date((new Date()).valueOf() - 1000 * 60 * 60 * 24 * i)),
      "release": 0,
      "beta": 0,
      "nightly": 0,
      "esr": 0,
      "all": 0
    });
  }

  // Process the Socorro data
  if (items.length >= 180) {
    var processed = [0, 0];
    var processed_groups = 0;
    $.each(signatures, function (i) {
      var processed_data = 0;
      // Set the report URL, this will be used to load the data report on click
      if (!globals.url[i]) globals.url[i] = "";
      globals.url[i] = globals.url_base + signatures[i];
      // Iterate through the Socorro data and create the chart data object
      var url = "https://crash-stats.mozilla.org/api/SuperSearch/?" + signatures[i] + "&date=%3E%3D" + start_date + "&date=%3C%3D" + end_date + "&_histogram.date=release_channel&_histogram_interval=1d&_results_number=0";
      url = url.replace("/?&signature", "/?signature");
      d3.json(url, function (data) {
        if (data.total > 0) {
          $.each(data, function (key, value) {
            if (key == "facets") {
              var histogram_date = value.histogram_date;
              processed[1] = processed[1] + (histogram_date.length - 1);
              $.each(histogram_date, function (key, value) {
                for (var j = 0; j < items.length; j++) {
                  if (items[j].date == value.term.substring(0, 10)) {
                    var channels = value.facets.release_channel;
                    $.each(value.facets.release_channel, function (channel_index, channel_data) {
                      if (Object.keys(items[j]).includes(channel_data.term)) {
                        items[j][channel_data.term] += channel_data.count;
                      }
                    });

                    items[j].all += value.count;
                  }
                }
                processed_data = processed_data + 1;
                if (processed_data >= histogram_date.length) processed_groups = processed_groups + 1;
                if (processed_groups >= signatures.length) draw();
              });
            }
          });
        } else {
          processed_groups += 1;
          if (processed_groups >= signatures.length) draw();
        }
      });
    });
  }
}
