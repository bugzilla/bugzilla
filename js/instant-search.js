/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var Dom = YAHOO.util.Dom;
var Event = YAHOO.util.Event;

Event.onDOMReady(function() {
  YAHOO.bugzilla.instantSearch.onInit();
  if (YAHOO.bugzilla.instantSearch.getContent().length >= 4) {
    YAHOO.bugzilla.instantSearch.doSearch(YAHOO.bugzilla.instantSearch.getContent());
  } else {
    YAHOO.bugzilla.instantSearch.reset();
  }
});

YAHOO.bugzilla.instantSearch = {
  dataTable: null,
  dataTableColumns: null,
  elContent: null,
  elList: null,
  currentSearchQuery: '',
  currentSearchProduct: '',

  onInit: function() {
    this.elContent = Dom.get('content');
    this.elList = Dom.get('results');

    Event.addListener(this.elContent, 'keyup', this.onContentKeyUp);
    Event.addListener(Dom.get('product'), 'change', this.onProductChange);
  },

  setLabels: function(labels) {
    this.dataTableColumns = [
      { key: "id", label: labels.id, formatter: this.formatId },
      { key: "summary", label: labels.summary, formatter: "text" },
      { key: "component", label: labels.component, formatter: "text" },
      { key: "status", label: labels.status, formatter: this.formatStatus },
    ];
  },

  initDataTable: function() {
    this.dataTable = new YAHOO.widget.DataTable(
      'results',
      this.dataTableColumns,
      new YAHOO.util.LocalDataSource([]), // Dummy data source
      {
        initialLoad: false,
        MSG_EMPTY: 'No matching bugs found.',
        MSG_ERROR: 'An error occurred while searching for bugs, please try again.'
      }
    );
  },

  formatId: function(el, oRecord, oColumn, oData) {
    el.innerHTML = `<a href="${BUGZILLA.config.basepath}show_bug.cgi?id=${oData}" target="_blank">${oData}</a>`;
  },

  formatStatus: function(el, oRecord, oColumn, oData) {
    var resolution = oRecord.getData('resolution');
    var bugStatus = display_value('bug_status', oData);
    if (resolution) {
      el.innerHTML = bugStatus + ' ' + display_value('resolution', resolution);
    } else {
      el.innerHTML = bugStatus;
    }
  },

  reset: function() {
    Dom.addClass(this.elList, 'hidden');
    this.elList.innerHTML = '';
    this.currentSearchQuery = '';
    this.currentSearchProduct = '';
  },

  onContentKeyUp: function(e) {
    clearTimeout(YAHOO.bugzilla.instantSearch.lastTimeout);
    YAHOO.bugzilla.instantSearch.lastTimeout = setTimeout(function() {
      YAHOO.bugzilla.instantSearch.doSearch(YAHOO.bugzilla.instantSearch.getContent()) },
      600);
  },

  onProductChange: function(e) {
    YAHOO.bugzilla.instantSearch.doSearch(YAHOO.bugzilla.instantSearch.getContent());
  },

  doSearch: async query => {
    if (query.length < 4)
      return;

    // don't query if we already have the results (or they are pending)
    var product = Dom.get('product').value;
    if (YAHOO.bugzilla.instantSearch.currentSearchQuery == query &&
        YAHOO.bugzilla.instantSearch.currentSearchProduct == product)
      return;
    YAHOO.bugzilla.instantSearch.currentSearchQuery = query;
    YAHOO.bugzilla.instantSearch.currentSearchProduct = product;

    // initialise the datatable as late as possible
    YAHOO.bugzilla.instantSearch.initDataTable();

    try {
      // run the search
      Dom.removeClass(YAHOO.bugzilla.instantSearch.elList, 'hidden');

      YAHOO.bugzilla.instantSearch.dataTable.showTableMessage(
        'Searching...&nbsp;&nbsp;&nbsp;' +
        `<img src="${BUGZILLA.config.basepath}extensions/GuidedBugEntry/web/images/throbber.gif"` +
        ' width="16" height="11">',
        YAHOO.widget.DataTable.CLASS_LOADING
      );

      let data;

      try {
        const { bugs } = await Bugzilla.API.get('bug/possible_duplicates', {
          product: YAHOO.bugzilla.instantSearch.getProduct(),
          summary: query,
          limit: 20,
          include_fields: ['id', 'summary', 'status', 'resolution', 'component'],
        });

        data = { results: bugs };
      } catch (ex) {
        YAHOO.bugzilla.instantSearch.currentSearchQuery = '';
        data = { error: true };
      }

      YAHOO.bugzilla.instantSearch.dataTable.onDataReturnInitializeTable('', data);
    } catch(err) {
      if (console)
        console.error(err.message);
    }
  },

  getContent: function() {
    var content = this.elContent.value.trim();
    // work around chrome bug
    if (content == YAHOO.bugzilla.instantSearch.elContent.getAttribute('placeholder')) {
      return '';
    } else {
      return content;
    }
  },

  getProduct: function() {
    var result = [];
    var name = Dom.get('product').value;
    result.push(name);
    if (products[name] && products[name].related) {
      for (var i = 0, n = products[name].related.length; i < n; i++) {
        result.push(products[name].related[i]);
      }
    }
    return result;
  }

};

