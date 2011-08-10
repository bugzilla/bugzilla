/*
  SortTable
  version 2
  7th April 2007
  Stuart Langridge, http://www.kryogenix.org/code/browser/sorttable/
  
  Instructions:
  Download this file
  Add <script src="sorttable.js"></script> to your HTML
  Add class="sortable" to any table you'd like to make sortable
  Click on the headers to sort
  
  Thanks to many, many people for contributions and suggestions.
  Licenced as X11: http://www.kryogenix.org/code/browser/licence.html
  This basically means: do what you want with it.
*/

var stIsIE = /*@cc_on!@*/false;

sorttable = {
  init: function() {
    // quit if this function has already been called
    if (arguments.callee.done) return;
    // flag this function so we don't do the same thing twice
    arguments.callee.done = true;
    // kill the timer
    if (_timer) clearInterval(_timer);
    
    if (!document.createElement || !document.getElementsByTagName) return;
    
    sorttable.DATE_RE = /^(\d\d?)[\/\.-](\d\d?)[\/\.-]((\d\d)?\d\d)$/;
    
    forEach(document.getElementsByTagName('table'), function(table) {
      if (table.className.search(/\bsortable\b/) != -1) {
        sorttable.makeSortable(table);
      }
    });
    
  },

  /* 
   * Prepares the table so that it can be sorted
   *
   */
  makeSortable: function(table) {

    if (table.getElementsByTagName('thead').length == 0) {
      // table doesn't have a tHead. Since it should have, create one and
      // put the first table row in it.
      the = document.createElement('thead');
      the.appendChild(table.rows[0]);
      table.insertBefore(the,table.firstChild);
    }
    // Safari doesn't support table.tHead, sigh
    if (table.tHead == null) table.tHead = table.getElementsByTagName('thead')[0];
    
    //if (table.tHead.rows.length != 1) return; // can't cope with two header rows
    
    // Sorttable v1 put rows with a class of "sortbottom" at the bottom (as
    // "total" rows, for example). This is B&R, since what you're supposed
    // to do is put them in a tfoot. So, if there are sortbottom rows,
    // for backwards compatibility, move them to tfoot (creating it if needed).
    sortbottomrows = [];
    for (var i=0; i<table.rows.length; i++) {
      if (table.rows[i].className.search(/\bsortbottom\b/) != -1) {
        sortbottomrows[sortbottomrows.length] = table.rows[i];
      }
    }

    if (sortbottomrows) {
      if (table.tFoot == null) {
        // table doesn't have a tfoot. Create one.
        tfo = document.createElement('tfoot');
        table.appendChild(tfo);
      }
      for (var i=0; i<sortbottomrows.length; i++) {
        tfo.appendChild(sortbottomrows[i]);
      }
      delete sortbottomrows;
    }

    sorttable._walk_through_headers(table);
  },

  /*
   * Helper function for preparing the table
   *
   */
  _walk_through_headers: function(table) {
      // First, gather some information we need to sort the table.
      var bodies = [];
      var table_rows = [];
      var body_size = table.tBodies[0].rows.length;

      // We need to get all the rows
      for (var i=0; i<table.tBodies.length; i++) {
        if (!table.tBodies[i].className.match(/\bsorttable_body\b/))
            continue;

        bodies[bodies.length] = table.tBodies[i];
        for (j=0; j<table.tBodies[i].rows.length; j++) {
          table_rows[table_rows.length] = table.tBodies[i].rows[j];
        }
      }

      table.sorttable_rows = table_rows;
      table.sorttable_body_size = body_size;
      table.sorttable_bodies = bodies;
      

      // work through each column and calculate its type

      // For each row in the header..
      for (var row_index=0; row_index < table.tHead.rows.length; row_index++) {

        headrow = table.tHead.rows[row_index].cells;
        // ... Walk through each column and calculate the type.
        for (var i=0; i<headrow.length; i++) {
            // Don't sort this column, please
            if (headrow[i].className.match(/\bsorttable_nosort\b/))  continue;

            // Override sort column index.
            column_index = i;
            mtch = headrow[i].className.match(/\bsortable_column_([a-z0-9]+)\b/);
            if (mtch) column_index = mtch[1];


            // Manually override the type with a sorttable_type attribute
            // Override sort function
            mtch = headrow[i].className.match(/\bsorttable_([a-z0-9]+)\b/);
            if (mtch) override = mtch[1];

            if (mtch && typeof sorttable["sort_"+override] == 'function') {
                headrow[i].sorttable_sortfunction = sorttable["sort_"+override];
            } else {
                headrow[i].sorttable_sortfunction = sorttable.guessType(table, column_index);
            }

            // make it clickable to sort
            headrow[i].sorttable_columnindex = column_index;
            headrow[i].table = table;

            // If the header contains a link, clear the href.
            for (var k=0; k<headrow[i].childNodes.length; k++) {
                if (headrow[i].childNodes[k].tagName == 'A') {
                  headrow[i].childNodes[k].href = "javascript:void(0);";
                }
            }

            dean_addEvent(headrow[i], "click", sorttable._on_column_header_clicked);

        } // inner for (var i=0; i<headrow.length; i++)
      } // outer for
  },




  /*
   * Helper function for the _on_column_header_clicked handler
   *
   */

  _remove_sorted_classes: function(header) {
    // For each row in the header..
    for (var j=0; j< header.rows.length; j++) {
        // ... Walk through each column and calculate the type.
        row = header.rows[j].cells;

        for (var i=0; i<row.length; i++) {
            cell = row[i];
            if (cell.nodeType != 1) return; // an element

            mtch = cell.className.match(/\bsorted_([0-9]+)\b/);
            if (mtch) {
                cell.className = cell.className.replace('sorted_'+mtch[1],
                                                        'sorted_'+(parseInt(mtch[1])+1));
            }

            cell.className = cell.className.replace('sorttable_sorted_reverse','');
            cell.className = cell.className.replace('sorttable_sorted','');
        }
    }
  },

  _check_already_sorted: function(cell) {
      if (cell.className.search(/\bsorttable_sorted\b/) != -1) {
         // if we're already sorted by this column, just 
         // reverse the table, which is quicker
         sorttable.reverse_table(cell);

         sorttable._mark_column_as_sorted(cell, '&#x25B2;', 1);
         return 1;
      }

      if (cell.className.search(/\bsorttable_sorted_reverse\b/) != -1) {
         // if we're already sorted by this column in reverse, just 
         // re-reverse the table, which is quicker
         sorttable.reverse_table(cell);

         sorttable._mark_column_as_sorted(cell, '&#x25BC;', 0);

         return 1;
      }

      return 0;
  },

  /* Visualy mark the cell as sorted.
   *
   * @param cell: the cell being marked
   * @param text: the text being used to mark. you can use html
   * @param reversed: whether the column is reversed or not.
   *
   */
  _mark_column_as_sorted: function(cell, text, reversed) {
      // remove eventual class
      cell.className = cell.className.replace('sorttable_sorted', '');
      cell.className = cell.className.replace('sorttable_sorted_reverse', '');

      // the column is reversed
      if (reversed) {
          cell.className += ' sorttable_sorted_reverse';
      }
      else {
          // remove eventual class
          cell.className += ' sorttable_sorted';
      }

      sorttable._remove_sorting_marker();

      marker = document.createElement('span');
      marker.id = "sorttable_sort_mark";
      marker.className = "bz_sort_order_primary";
      marker.innerHTML = text;
      cell.appendChild(marker);
  },

  _remove_sorting_marker: function() {
      mark = document.getElementById('sorttable_sort_mark');
      if (mark) { mark.parentNode.removeChild(mark); }
      els = sorttable._getElementsByClassName('bz_sort_order_primary');
      for(var i=0,j=els.length; i<j; i++) {
        els[i].parentNode.removeChild(els[i]);
      }
      els = sorttable._getElementsByClassName('bz_sort_order_secondary');
      for(var i=0,j=els.length; i<j; i++) {
        els[i].parentNode.removeChild(els[i]);
      }
  },

  _getElementsByClassName: function(classname, node) {
      if(!node) node = document.getElementsByTagName("body")[0];
      var a = [];
      var re = new RegExp('\\b' + classname + '\\b');
      var els = node.getElementsByTagName("*");
      for(var i=0,j=els.length; i<j; i++)
        if(re.test(els[i].className))a.push(els[i]);
      return a;
  },

  /*
   * This is the callback for when the table header is clicked.
   *
   * @param evt: the event that triggered this callback
   */
  _on_column_header_clicked: function(evt) {

      // The table is already sorted by this column. Just reverse it.
      if (sorttable._check_already_sorted(this))
        return;


      // First, remove sorttable_sorted classes from the other header 
      // that is currently sorted and its marker (the simbol indicating
      // that its sorted.
      sorttable._remove_sorted_classes(this.table.tHead);
      mtch = this.className.match(/\bsorted_([0-9]+)\b/);
      if (mtch) {
          this.className = this.className.replace('sorted_'+mtch[1], '');
      }
      this.className += ' sorted_0 ';

      // This is the text that indicates that the column is sorted.
      sorttable._mark_column_as_sorted(this, '&#x25BC;', 0);

      sorttable.sort_table(this);
      
  },

  sort_table: function(cell) {
      // build an array to sort. This is a Schwartzian transform thing,
      // i.e., we "decorate" each row with the actual sort key,
      // sort based on the sort keys, and then put the rows back in order
      // which is a lot faster because you only do getInnerText once per row
      col = cell.sorttable_columnindex;
      rows = cell.table.sorttable_rows;

      var BUGLIST = '';

      for (var j = 0; j < cell.table.sorttable_rows.length; j++) {
          rows[j].sort_data = sorttable.getInnerText(rows[j].cells[col]);
      }

      /* If you want a stable sort, uncomment the following line */
      sorttable.shaker_sort(rows, cell.sorttable_sortfunction);
      /* and comment out this one */
      //rows.sort(cell.sorttable_sortfunction);

      // Rebuild the table, using he sorted rows.
      tb = cell.table.sorttable_bodies[0];
      body_size = cell.table.sorttable_body_size;
      body_index = 0;

      for (var j=0; j<rows.length; j++) {    
          if (j % 2)
              rows[j].className = rows[j].className.replace('bz_row_even',
                                                            'bz_row_odd');
          else
              rows[j].className = rows[j].className.replace('bz_row_odd',
                                                            'bz_row_even');

          tb.appendChild(rows[j]);
          var bug_id = sorttable.getInnerText(rows[j].cells[0].childNodes[1]);
          BUGLIST = BUGLIST ? BUGLIST+':'+bug_id : bug_id;

          if (j % body_size == body_size-1) {
            body_index++;
            if (body_index < cell.table.sorttable_bodies.length) {
                tb = cell.table.sorttable_bodies[body_index];
            }
          }
      }

      document.cookie = 'BUGLIST='+BUGLIST;

      cell.table.sorttable_rows = rows;
  },
  
  reverse_table: function(cell) {
    oldrows = cell.table.sorttable_rows;
    newrows = [];

    for (var i=0; i < oldrows.length; i++) {
        newrows[newrows.length] = oldrows[i];
    }

    tb = cell.table.sorttable_bodies[0];
    body_size = cell.table.sorttable_body_size;
    body_index = 0;
  
    var BUGLIST = '';

    cell.table.sorttable_rows = [];
    for (var i = newrows.length-1; i >= 0; i--) {
        if (i % 2)
            newrows[i].className = newrows[i].className.replace('bz_row_even',
                                                                'bz_row_odd');
        else
            newrows[i].className = newrows[i].className.replace('bz_row_odd',
                                                                'bz_row_even');

        tb.appendChild(newrows[i]);
        cell.table.sorttable_rows.push(newrows[i]);

        var bug_id = sorttable.getInnerText(newrows[i].cells[0].childNodes[1]);
        BUGLIST = BUGLIST ? BUGLIST+':'+bug_id : bug_id;

        if ((newrows.length-1-i) % body_size == body_size-1) {
            body_index++;
            if (body_index < cell.table.sorttable_bodies.length) {
                tb = cell.table.sorttable_bodies[body_index];
            }
        }

    }

    document.cookie = 'BUGLIST='+BUGLIST;

    delete newrows;
  },
  
  guessType: function(table, column) {
    // guess the type of a column based on its first non-blank row
    sortfn = sorttable.sort_alpha;
    for (var i=0; i<table.sorttable_bodies[0].rows.length; i++) {
      text = sorttable.getInnerText(table.sorttable_bodies[0].rows[i].cells[column]);
      if (text != '') {
        if (text.match(/^-?[£$¤]?[\d,.]+%?$/)) {
          return sorttable.sort_numeric;
        }
        // check for a date: dd/mm/yyyy or dd/mm/yy 
        // can have / or . or - as separator
        // can be mm/dd as well
        possdate = text.match(sorttable.DATE_RE)
        if (possdate) {
          // looks like a date
          first = parseInt(possdate[1]);
          second = parseInt(possdate[2]);
          if (first > 12) {
            // definitely dd/mm
            return sorttable.sort_ddmm;
          } else if (second > 12) {
            return sorttable.sort_mmdd;
          } else {
            // looks like a date, but we can't tell which, so assume
            // that it's dd/mm (English imperialism!) and keep looking
            sortfn = sorttable.sort_ddmm;
          }
        }
      }
    }
    return sortfn;
  },
  
  getInnerText: function(node) {
    // gets the text we want to use for sorting for a cell.
    // strips leading and trailing whitespace.
    // this is *not* a generic getInnerText function; it's special to sorttable.
    // for example, you can override the cell text with a customkey attribute.
    // it also gets .value for <input> fields.

    hasInputs = (typeof node.getElementsByTagName == 'function') &&
                 node.getElementsByTagName('input').length;
    
    if (typeof node.getAttribute != 'undefined' && node.getAttribute("sorttable_customkey") != null) {
      return node.getAttribute("sorttable_customkey");
    }
    else if (typeof node.textContent != 'undefined' && !hasInputs) {
      return node.textContent.replace(/^\s+|\s+$/g, '');
    }
    else if (typeof node.innerText != 'undefined' && !hasInputs) {
      return node.innerText.replace(/^\s+|\s+$/g, '');
    }
    else if (typeof node.text != 'undefined' && !hasInputs) {
      return node.text.replace(/^\s+|\s+$/g, '');
    }
    else {
      switch (node.nodeType) {
        case 3:
          if (node.nodeName.toLowerCase() == 'input') {
            return node.value.replace(/^\s+|\s+$/g, '');
          }
        case 4:
          return node.nodeValue.replace(/^\s+|\s+$/g, '');
          break;
        case 1:
        case 11:
          var innerText = '';
          for (var i = 0; i < node.childNodes.length; i++) {
            innerText += sorttable.getInnerText(node.childNodes[i]);
          }
          return innerText.replace(/^\s+|\s+$/g, '');
          break;
        default:
          return '';
      }
    }
  },
  
  /* sort functions
     each sort function takes two parameters, a and b
     you are comparing a.sort_data and b.sort_data */
  sort_numeric: function(a,b) {
    aa = parseFloat(a.sort_data.replace(/[^0-9.-]/g,''));
    if (isNaN(aa)) aa = 0;
    bb = parseFloat(b.sort_data.replace(/[^0-9.-]/g,'')); 
    if (isNaN(bb)) bb = 0;
    return aa-bb;
  },

  sort_alpha: function(a,b) {
    if (a.sort_data.toLowerCase()==b.sort_data.toLowerCase()) return 0;
    if (a.sort_data.toLowerCase()<b.sort_data.toLowerCase()) return -1;
    return 1;
  },

  sort_ddmm: function(a,b) {
    mtch = a.sort_data.match(sorttable.DATE_RE);
    y = mtch[3]; m = mtch[2]; d = mtch[1];
    if (m.length == 1) m = '0'+m;
    if (d.length == 1) d = '0'+d;
    dt1 = y+m+d;
    mtch = b.sort_data.match(sorttable.DATE_RE);
    y = mtch[3]; m = mtch[2]; d = mtch[1];
    if (m.length == 1) m = '0'+m;
    if (d.length == 1) d = '0'+d;
    dt2 = y+m+d;
    if (dt1==dt2) return 0;
    if (dt1<dt2) return -1;
    return 1;
  },

  sort_mmdd: function(a,b) {
    mtch = a.sort_data.match(sorttable.DATE_RE);
    y = mtch[3]; d = mtch[2]; m = mtch[1];
    if (m.length == 1) m = '0'+m;
    if (d.length == 1) d = '0'+d;
    dt1 = y+m+d;
    mtch = b.sort_data.match(sorttable.DATE_RE);
    y = mtch[3]; d = mtch[2]; m = mtch[1];
    if (m.length == 1) m = '0'+m;
    if (d.length == 1) d = '0'+d;
    dt2 = y+m+d;
    if (dt1==dt2) return 0;
    if (dt1<dt2) return -1;
    return 1;
  },
  
  shaker_sort: function(list, comp_func) {
    // A stable sort function to allow multi-level sorting of data
    // see: http://en.wikipedia.org/wiki/Cocktail_sort
    // thanks to Joseph Nahmias
    var b = 0;
    var t = list.length - 1;
    var swap = true;

    while(swap) {
        swap = false;
        for(var i = b; i < t; ++i) {
            if ( comp_func(list[i], list[i+1]) > 0 ) {
                var q = list[i]; list[i] = list[i+1]; list[i+1] = q;
                swap = true;
            }
        } // for
        t--;

        if (!swap) break;

        for(var i = t; i > b; --i) {
            if ( comp_func(list[i], list[i-1]) < 0 ) {
                var q = list[i]; list[i] = list[i-1]; list[i-1] = q;
                swap = true;
            }
        } // for
        b++;

    } // while(swap)
  }  
}

/* ******************************************************************
   Supporting functions: bundled here to avoid depending on a library
   ****************************************************************** */

// Dean Edwards/Matthias Miller/John Resig

/* for Mozilla/Opera9 */
if (document.addEventListener) {
    document.addEventListener("DOMContentLoaded", sorttable.init, false);
}

/* for Internet Explorer */
/*@cc_on @*/
/*@if (@_win32)
    // IE doesn't have a way to test if the DOM is loaded
    // doing a deferred script load with onReadyStateChange checks is
    // problematic, so poll the document until it is scrollable
    // http://blogs.atlassian.com/developer/2008/03/when_ie_says_dom_is_ready_but.html
    var loadTestTimer = function() {
        try {
            if (document.readyState != "loaded" && document.readyState != "complete") {
                document.documentElement.doScroll("left");
            }
            sorttable.init(); // call the onload handler
        } catch(error) {
            setTimeout(loadTestTimer, 100);
        }
    };
    loadTestTimer();
/*@end @*/

/* for Safari */
if (/WebKit/i.test(navigator.userAgent)) { // sniff
    var _timer = setInterval(function() {
        if (/loaded|complete/.test(document.readyState)) {
            sorttable.init(); // call the onload handler
        }
    }, 10);
}

/* for other browsers */
window.onload = sorttable.init;

// written by Dean Edwards, 2005
// with input from Tino Zijdel, Matthias Miller, Diego Perini

// http://dean.edwards.name/weblog/2005/10/add-event/

function dean_addEvent(element, type, handler) {
	if (element.addEventListener) {
		element.addEventListener(type, handler, false);
	} else {
		// assign each event handler a unique ID
		if (!handler.$$guid) handler.$$guid = dean_addEvent.guid++;
		// create a hash table of event types for the element
		if (!element.events) element.events = {};
		// create a hash table of event handlers for each element/event pair
		var handlers = element.events[type];
		if (!handlers) {
			handlers = element.events[type] = {};
			// store the existing event handler (if there is one)
			if (element["on" + type]) {
				handlers[0] = element["on" + type];
			}
		}
		// store the event handler in the hash table
		handlers[handler.$$guid] = handler;
		// assign a global event handler to do all the work
		element["on" + type] = handleEvent;
	}
};
// a counter used to create unique IDs
dean_addEvent.guid = 1;

function removeEvent(element, type, handler) {
	if (element.removeEventListener) {
		element.removeEventListener(type, handler, false);
	} else {
		// delete the event handler from the hash table
		if (element.events && element.events[type]) {
			delete element.events[type][handler.$$guid];
		}
	}
};

function handleEvent(event) {
	var returnValue = true;
	// grab the event object (IE uses a global event object)
	event = event || fixEvent(((this.ownerDocument || this.document || this).parentWindow || window).event);
	// get a reference to the hash table of event handlers
	var handlers = this.events[event.type];
	// execute each event handler
	for (var i in handlers) {
		this.$$handleEvent = handlers[i];
		if (this.$$handleEvent(event) === false) {
			returnValue = false;
		}
	}
	return returnValue;
};

function fixEvent(event) {
	// add W3C standard event methods
	event.preventDefault = fixEvent.preventDefault;
	event.stopPropagation = fixEvent.stopPropagation;
	return event;
};
fixEvent.preventDefault = function() {
	this.returnValue = false;
};
fixEvent.stopPropagation = function() {
  this.cancelBubble = true;
}

// Dean's forEach: http://dean.edwards.name/base/forEach.js
/*
	forEach, version 1.0
	Copyright 2006, Dean Edwards
	License: http://www.opensource.org/licenses/mit-license.php
*/

// array-like enumeration
if (!Array.forEach) { // mozilla already supports this
	Array.forEach = function(array, block, context) {
		for (var i = 0; i < array.length; i++) {
			block.call(context, array[i], i, array);
		}
	};
}

// generic enumeration
Function.prototype.forEach = function(object, block, context) {
	for (var key in object) {
		if (typeof this.prototype[key] == "undefined") {
			block.call(context, object[key], key, object);
		}
	}
};

// character enumeration
String.forEach = function(string, block, context) {
	Array.forEach(string.split(""), function(chr, index) {
		block.call(context, chr, index, string);
	});
};

// globally resolve forEach enumeration
var forEach = function(object, block, context) {
	if (object) {
		var resolve = Object; // default
		if (object instanceof Function) {
			// functions have a "length" property
			resolve = Function;
		} else if (object.forEach instanceof Function) {
			// the object implements a custom forEach method so use that
			object.forEach(block, context);
			return;
		} else if (typeof object == "string") {
			// the object is a string
			resolve = String;
		} else if (typeof object.length == "number") {
			// the object is array-like
			resolve = Array;
		}
		resolve.forEach(object, block, context);
	}
};

