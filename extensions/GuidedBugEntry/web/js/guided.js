/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

// global

var Dom = YAHOO.util.Dom;
var Event = YAHOO.util.Event;
var History = YAHOO.util.History;

var guided = {
  _currentStep: '',
  detectedPlatform: '',
  detectedOpSys: '',
  currentUser: '',
  openStates: [],

  setStep: function(newStep, noSetHistory) {
    // initialise new step
    switch(newStep) {
      case 'product':
        product.onShow();
        break;
      case 'otherProducts':
        otherProducts.onShow();
        break;
      case 'dupes':
        dupes.onShow();
        break;
      case 'bugForm':
        bugForm.onShow();
        break;
      default:
        guided.setStep('product');
        return;
    }

    // change visibility of _step div
    if (this._currentStep)
      Dom.addClass(this._currentStep + '_step', 'hidden');
    this._currentStep = newStep;
    Dom.removeClass(this._currentStep + '_step', 'hidden');

    // scroll to top of page to mimic real navigation
    scroll(0,0);

    // update history
    if (History && !noSetHistory) {
      History.navigate('h', newStep + '|' + product.getName() +
                            (product.getPreselectedComponent() ? '|' + product.getPreselectedComponent() : '')
      );
    }
  },

  init: function() {
    // init history manager
    try {
      History.register('h', History.getBookmarkedState('h') || 'product',
        this._onStateChange);
      History.initialize("yui-history-field", "yui-history-iframe");
      History.onReady(function () {
        guided._onStateChange(History.getCurrentState('h'), true);
      });
    } catch(err) {
      History = false;
    }

    // init steps
    product.onInit();
    dupes.onInit();
    bugForm.onInit();
  },

  _onStateChange: function(state, noSetHistory) {
    state = state.split('|');
    product.setName(state[1] || '');
    product.setPreselectedComponent(state[2] || '');
    guided.setStep(state[0], noSetHistory);
  },

  setAdvancedLink: function() {
    href = 'enter_bug.cgi?format=__default__' +
      '&product=' + encodeURIComponent(product.getName()) +
      '&short_desc=' + encodeURIComponent(dupes.getSummary());
    Dom.get('advanced_img').href = href;
    Dom.get('advanced_link').href = href;
  }
};

// product step

var product = {
  details: false,
  _counter: 0,
  _loaded: '',
  _preselectedComponent: '',

  onInit: function() { },

  onShow: function() {
    Dom.removeClass('advanced', 'hidden');
  },

  select: function(productName) {
    // called when a product is selected
    this.setName(productName);
    dupes.reset();
    guided.setStep('dupes');
  },

  getName: function() {
    return Dom.get('product').value;
  },

  getPreselectedComponent: function() {
    return this._preselectedComponent;
  },

  setPreselectedComponent: function(value) {
    this._preselectedComponent = value;
  },

  _getNameAndRelated: function() {
    var result = [];

    var name = this.getName();
    result.push(name);

    if (products[name] && products[name].related) {
      for (var i = 0, n = products[name].related.length; i < n; i++) {
        result.push(products[name].related[i]);
      }
    }

    return result;
  },

  setName: function(productName) {
    if (productName == this.getName() && this.details)
      return;

    // display the product name
    Dom.get('product').value = productName;
    Dom.get('product_label').innerHTML = YAHOO.lang.escapeHTML(productName);
    Dom.get('dupes_product_name').innerHTML = YAHOO.lang.escapeHTML(productName);
    Dom.get('list_comp').href = 'describecomponents.cgi?product=' + encodeURIComponent(productName);
    guided.setAdvancedLink();

    if (productName == '') {
      Dom.addClass("product_support", "hidden");
      return;
    }

    // use the correct security group
    if (products[productName] && products[productName].secgroup) {
      Dom.get('groups').value = products[productName].secgroup;
    } else {
      Dom.get('groups').value = products['_default'].secgroup;
    }

    // use the correct platform & op_sys
    if (products[productName] && products[productName].detectPlatform) {
      Dom.get('rep_platform').value = guided.detectedPlatform;
      Dom.get('op_sys').value = guided.detectedOpSys;
    } else {
      Dom.get('rep_platform').value = 'All';
      Dom.get('op_sys').value = 'All';
    }

    // show support message
    if (products[productName] && products[productName].support) {
      Dom.get("product_support_message").innerHTML = products[productName].support;
      Dom.removeClass("product_support", "hidden");
    } else {
      Dom.addClass("product_support", "hidden");
    }

    // show/hide component selection row
    if (products[productName] && products[productName].noComponentSelection) {
      if (!Dom.hasClass('componentTR', 'hidden')) {
        Dom.addClass('componentTR', 'hidden');
        bugForm.toggleOddEven();
      }
    } else {
      if (Dom.hasClass('componentTR', 'hidden')) {
        Dom.removeClass('componentTR', 'hidden');
        bugForm.toggleOddEven();
      }
    }

    if (this._loaded == productName)
      return;

    // grab the product information
    this.details = false;
    this._loaded = productName;
    YAHOO.util.Connect.setDefaultPostHeader('application/json; charset=UTF-8');
    YAHOO.util.Connect.asyncRequest(
      'POST',
      'jsonrpc.cgi',
      {
        success: function(res) {
          try {
            data = YAHOO.lang.JSON.parse(res.responseText);
            if (data.error)
              throw(data.error.message);
            product.details = data.result.products[0];
            bugForm.onProductUpdated();
          } catch (err) {
            product.details = false;
            bugForm.onProductUpdated();
            if (err) {
              alert('Failed to retreive components for product "' +
                productName + '":' + "\n\n" + err);
              if (console)
                console.error(err);
            }
          }
        },
        failure: function(res) {
          this._loaded = '';
          product.details = false;
          bugForm.onProductUpdated();
          if (res.responseText) {
            alert('Failed to retreive components for product "' +
              productName + '":' + "\n\n" + res.responseText);
            if (console)
              console.error(res);
          }
        }
      },
      YAHOO.lang.JSON.stringify({
        version: "1.1",
        method: "Product.get",
        id: ++this._counter,
        params: {
          names: [productName],
          exclude_fields: ['internals', 'milestones']
        }
      }
      )
    );
  }
};

// other products step

var otherProducts = {
  onInit: function() { },

  onShow: function() {
    Dom.removeClass('advanced', 'hidden');
  }
};

// duplicates step

var dupes = {
  _counter: 0,
  _dataTable: null,
  _dataTableColumns: null,
  _elSummary: null,
  _elSearch: null,
  _elList: null,
  _currentSearchQuery: '',

  onInit: function() {
    this._elSummary = Dom.get('dupes_summary');
    this._elSearch = Dom.get('dupes_search');
    this._elList = Dom.get('dupes_list');

    Event.onBlur(this._elSummary, this._onSummaryBlur);
    Event.addListener(this._elSummary, 'input', this._onSummaryBlur);
    Event.addListener(this._elSummary, 'keydown', this._onSummaryKeyDown);
    Event.addListener(this._elSummary, 'keyup', this._onSummaryKeyUp);
    Event.addListener(this._elSearch, 'click', this._doSearch);
  },

  setLabels: function(labels) {
    this._dataTableColumns = [
      { key: "id", label: labels.id, formatter: this._formatId },
      { key: "summary", label: labels.summary, formatter: "text" },
      { key: "component", label: labels.component, formatter: "text" },
      { key: "status", label: labels.status, formatter: this._formatStatus },
      { key: "update_token", label: '', formatter: this._formatCc }
    ];
  },

  _initDataTable: function() {
    var dataSource = new YAHOO.util.XHRDataSource("jsonrpc.cgi");
    dataSource.connTimeout = 15000;
    dataSource.connMethodPost = true;
    dataSource.connXhrMode = "cancelStaleRequests";
    dataSource.maxCacheEntries = 3;
    dataSource.responseSchema = {
      resultsList : "result.bugs",
      metaFields : { error: "error", jsonRpcId: "id" }
    };
    // DataSource can't understand a JSON-RPC error response, so
    // we have to modify the result data if we get one.
    dataSource.doBeforeParseData = 
      function(oRequest, oFullResponse, oCallback) {
        if (oFullResponse.error) {
          oFullResponse.result = {};
          oFullResponse.result.bugs = [];
          if (console)
            console.error("JSON-RPC error:", oFullResponse.error);
        }
        return oFullResponse;
      };
    dataSource.subscribe('dataErrorEvent', 
      function() {
        dupes._currentSearchQuery = '';
      }
    );

    this._dataTable = new YAHOO.widget.DataTable(
      'dupes_list', 
      this._dataTableColumns, 
      dataSource, 
      { 
        initialLoad: false,
        MSG_EMPTY: 'No similar issues found.',
        MSG_ERROR: 'An error occurred while searching for similar issues,' +
          ' please try again.'
      }
    );
  },

  _formatId: function(el, oRecord, oColumn, oData) {
    el.innerHTML = '<a href="show_bug.cgi?id=' + oData +
      '" target="_blank">' + oData + '</a>';
  },

  _formatStatus: function(el, oRecord, oColumn, oData) {
    var resolution = oRecord.getData('resolution');
    var bug_status = display_value('bug_status', oData);
    if (resolution) {
      el.innerHTML = bug_status + ' ' +
        display_value('resolution', resolution);
    } else {
      el.innerHTML = bug_status;
    }
  },

  _formatCc: function(el, oRecord, oColumn, oData) {
   var cc = oRecord.getData('cc');
    var isCCed = false;
    for (var i = 0, n = cc.length; i < n; i++) {
      if (cc[i] == guided.currentUser) {
        isCCed = true;
        break;
      }
    }
    dupes._buildCcHTML(el, oRecord.getData('id'), oRecord.getData('status'),
      isCCed);
  },

  _buildCcHTML: function(el, id, bugStatus, isCCed) {
    while (el.childNodes.length > 0)
      el.removeChild(el.firstChild);

    var isOpen = false;
    for (var i = 0, n = guided.openStates.length; i < n; i++) {
      if (guided.openStates[i] == bugStatus) {
        isOpen = true;
        break;
      }
    }

    if (!isOpen && !isCCed) {
      // you can't cc yourself to a closed bug here
      return;
    }

    var button = document.createElement('button');
    button.setAttribute('type', 'button');
    if (isCCed) {
      button.innerHTML = 'Stop&nbsp;following';
      button.onclick = function() {
        dupes.updateFollowing(el, id, bugStatus, button, false); return false;
      };
    } else {
      button.innerHTML = 'Follow&nbsp;bug';
      button.onclick = function() {
        dupes.updateFollowing(el, id, bugStatus, button, true); return false;
      };
    }
    el.appendChild(button);
  },

  updateFollowing: function(el, bugID, bugStatus, button, follow) {
    button.disabled = true;
    button.innerHTML = 'Updating...';

    var ccObject;
    if (follow) {
      ccObject = { add: [ guided.currentUser ] };
    } else {
      ccObject = { remove: [ guided.currentUser ] };
    }

    YAHOO.util.Connect.setDefaultPostHeader('application/json; charset=UTF-8');
    YAHOO.util.Connect.asyncRequest(
      'POST',
      'jsonrpc.cgi',
      {
        success: function(res) {
          data = YAHOO.lang.JSON.parse(res.responseText);
          if (data.error)
            throw(data.error.message);
          dupes._buildCcHTML(el, bugID, bugStatus, follow);
        },
        failure: function(res) {
          dupes._buildCcHTML(el, bugID, bugStatus, !follow);
          if (res.responseText)
            alert("Update failed:\n\n" + res.responseText);
        }
      },
      YAHOO.lang.JSON.stringify({
        version: "1.1",
        method: "Bug.update",
        id: ++this._counter,
        params: {
          ids: [ bugID ],
          cc : ccObject
        }
      })
    );
  },

  reset: function() {
    this._elSummary.value = '';
    Dom.addClass(this._elList, 'hidden');
    Dom.addClass('dupes_continue', 'hidden');
    this._elList.innerHTML = '';
    this._showProductSupport();
    this._currentSearchQuery = '';
  },

  _showProductSupport: function() {
    var elSupport = Dom.get('product_support_' +
      product.getName().replace(' ', '_').toLowerCase());
    var supportElements = Dom.getElementsByClassName('product_support');
    for (var i = 0, n = supportElements.length; i < n; i++) {
      if (supportElements[i] == elSupport) {
        Dom.removeClass(elSupport, 'hidden');
      } else {
        Dom.addClass(supportElements[i], 'hidden');
      }
    }
  },

  onShow: function() {
    this._showProductSupport();
    this._onSummaryBlur();

    // hide the advanced form and top continue button entry until
    // a search has happened
    Dom.addClass('advanced', 'hidden');
    Dom.addClass('dupes_continue_button_top', 'hidden');

    if (!this._elSearch.disabled && this.getSummary().length >= 4) {
      // do an immediate search after a page refresh if there's a query
      this._doSearch();

    } else {
      // prepare for a search
      this.reset();
    }
  },

  _onSummaryBlur: function() {
    dupes._elSearch.disabled = dupes._elSummary.value == '';
    guided.setAdvancedLink();
  },

  _onSummaryKeyDown: function(e) {
    // map <enter> to doSearch()
    if (e && (e.keyCode == 13)) {
      dupes._doSearch();
      Event.stopPropagation(e);
    }
  },

  _onSummaryKeyUp: function(e) {
    // disable search button until there's a query
    dupes._elSearch.disabled = YAHOO.lang.trim(dupes._elSummary.value) == '';
  },

  _doSearch: function() {
    if (dupes.getSummary().length < 4) {
      alert('The summary must be at least 4 characters long.');
      return;
    }
    dupes._elSummary.blur();

    // don't query if we already have the results (or they are pending)
    if (dupes._currentSearchQuery == dupes.getSummary())
      return;
    dupes._currentSearchQuery = dupes.getSummary();

    // initialise the datatable as late as possible
    dupes._initDataTable();

    try {
      // run the search
      Dom.removeClass(dupes._elList, 'hidden');

      dupes._dataTable.showTableMessage(
        'Searching for similar issues...&nbsp;&nbsp;&nbsp;' +
        '<img src="extensions/GuidedBugEntry/web/images/throbber.gif"' + 
        ' width="16" height="11">',
        YAHOO.widget.DataTable.CLASS_LOADING
      );
      var json_object = {
          version: "1.1",
          method: "Bug.possible_duplicates",
          id: ++dupes._counter,
          params: {
              product: product._getNameAndRelated(),
              summary: dupes.getSummary(),
              limit: 12,
              include_fields: [ "id", "summary", "status", "resolution",
                "update_token", "cc", "component" ]
          }
      };

      dupes._dataTable.getDataSource().sendRequest(
        YAHOO.lang.JSON.stringify(json_object), 
        {
          success: dupes._onDupeResults,
          failure: dupes._onDupeResults,
          scope: dupes._dataTable,
          argument: dupes._dataTable.getState() 
        }
      );

      Dom.get('dupes_continue_button_top').disabled = true;
      Dom.get('dupes_continue_button_bottom').disabled = true;
      Dom.removeClass('dupes_continue', 'hidden');
    } catch(err) {
      if (console)
        console.error(err.message);
    }
  },

  _onDupeResults: function(sRequest, oResponse, oPayload) {
    Dom.removeClass('advanced', 'hidden');
    Dom.removeClass('dupes_continue_button_top', 'hidden');
    Dom.get('dupes_continue_button_top').disabled = false;
    Dom.get('dupes_continue_button_bottom').disabled = false;
    dupes._dataTable.onDataReturnInitializeTable(sRequest, oResponse,
      oPayload);
  },

  getSummary: function() {
    var summary = YAHOO.lang.trim(this._elSummary.value);
    // work around chrome bug
    if (summary == dupes._elSummary.getAttribute('placeholder')) {
      return '';
    } else {
      return summary;
    }
  }
};

// bug form step

var bugForm = {
  _visibleHelpPanel: null,
  _mandatoryFields: [],

  onInit: function() {
    Dom.get('user_agent').value = navigator.userAgent;
    if (navigator.buildID && navigator.buildID != navigator.userAgent) {
      Dom.get('build_id').value = navigator.buildID;
    }
    Event.addListener(Dom.get('short_desc'), 'blur', function() {
      Dom.get('dupes_summary').value = Dom.get('short_desc').value;
      guided.setAdvancedLink();
    });
  },

  onShow: function() {
    Dom.removeClass('advanced', 'hidden');
    // default the summary to the dupes query
    Dom.get('short_desc').value = dupes.getSummary();
    this.resetSubmitButton();
    if (Dom.get('component_select').length == 0)
      this.onProductUpdated();
    this.onFileChange();
    for (var i = 0, n = this._mandatoryFields.length; i < n; i++) {
      Dom.removeClass(this._mandatoryFields[i], 'missing');
    }
  },

  resetSubmitButton: function() {
    Dom.get('submit').disabled = false;
    Dom.get('submit').value = 'Submit Bug';
  },

  onProductUpdated: function() {
    var productName = product.getName();

    // init
    var elComponents = Dom.get('component_select');
    Dom.addClass('component_description', 'hidden');
    elComponents.options.length = 0;

    var elVersions = Dom.get('version_select');
    elVersions.length = 0;

    // product not loaded yet, bail out
    if (!product.details) {
      Dom.addClass('versionTH', 'hidden');
      Dom.addClass('versionTD', 'hidden');
      Dom.get('productTD').colSpan = 2;
      Dom.get('submit').disabled = true;
      return;
    }
    Dom.get('submit').disabled = false;

    // filter components
    if (products[productName] && products[productName].componentFilter) {
        product.details.components = products[productName].componentFilter(product.details.components);
    }

    // build components

    var elComponent = Dom.get('component');
    if (products[productName] && products[productName].noComponentSelection) {

      elComponent.value = products[productName].defaultComponent;
      bugForm._mandatoryFields = [ 'short_desc', 'version_select' ];

    } else {

      bugForm._mandatoryFields = [ 'short_desc', 'component_select', 'version_select' ];

      // check for the default component
      var defaultRegex;
      if (product.getPreselectedComponent()) {
        defaultRegex = new RegExp('^' + quoteMeta(product.getPreselectedComponent()) + '$', 'i')
      } else if(products[productName] && products[productName].defaultComponent) {
        defaultRegex = new RegExp('^' + quoteMeta(products[productName].defaultComponent) + '$', 'i')
      } else {
        defaultRegex = new RegExp('General', 'i');
      }

      var preselectedComponent = false;
      for (var i = 0, n = product.details.components.length; i < n; i++) {
        var component = product.details.components[i];
        if (component.is_active == '1') {
          if (defaultRegex.test(component.name)) {
            preselectedComponent = component.name;
            break;
          }
        }
      }

      // if there isn't a default component, default to blank
      if (!preselectedComponent) {
        elComponents.options[elComponents.options.length] = new Option('', '');
      }

      // build component select
      for (var i = 0, n = product.details.components.length; i < n; i++) {
        var component = product.details.components[i];
        if (component.is_active == '1') {
          elComponents.options[elComponents.options.length] =
            new Option(component.name, component.name);
        }
      }

      var validComponent = false;
      for (var i = 0, n = elComponents.options.length; i < n && !validComponent; i++) {
        if (elComponents.options[i].value == elComponent.value)
          validComponent = true;
      }
      if (!validComponent)
        elComponent.value = '';
      if (elComponent.value == '' && preselectedComponent)
        elComponent.value = preselectedComponent;
      if (elComponent.value != '') {
        elComponents.value = elComponent.value;
        this.onComponentChange(elComponent.value);
      }

    }

    // build versions
    var defaultVersion = '';
    var currentVersion = Dom.get('version').value;
    for (var i = 0, n = product.details.versions.length; i < n; i++) {
      var version = product.details.versions[i];
      if (version.is_active == '1') {
        elVersions.options[elVersions.options.length] =
          new Option(version.name, version.name);
        if (currentVersion == version.name)
          defaultVersion = version.name;
      }
    }

    if (!defaultVersion) {
      // try to detect version on a per-product basis
      if (products[productName] && products[productName].version) {
        var detectedVersion = products[productName].version();
        var options = elVersions.options;
        for (var i = 0, n = options.length; i < n; i++) {
          if (options[i].value == detectedVersion) {
            defaultVersion = detectedVersion;
            break;
          }
        }
      }
    }
    if (!defaultVersion) {
      // load last selected version
      defaultVersion = YAHOO.util.Cookie.get('VERSION-' + productName);
    }

    if (elVersions.length > 1) {
      // more than one version, show select
      Dom.get('productTD').colSpan = 1;
      Dom.removeClass('versionTH', 'hidden');
      Dom.removeClass('versionTD', 'hidden');

    } else {
      // if there's only one version, we don't need to ask the user
      Dom.addClass('versionTH', 'hidden');
      Dom.addClass('versionTD', 'hidden');
      Dom.get('productTD').colSpan = 2;
      defaultVersion = elVersions.options[0].value;
    }

    if (defaultVersion) {
      elVersions.value = defaultVersion;

    } else {
      // no default version, select an empty value to force a decision
      var opt = new Option('', '');
      try {
        // standards
        elVersions.add(opt, elVersions.options[0]);
      } catch(ex) {
        // ie only
        elVersions.add(opt, 0);
      }
      elVersions.value = '';
    }
    bugForm.onVersionChange(elVersions.value);
  },

  onComponentChange: function(componentName) {
    // show the component description
    Dom.get('component').value = componentName;
    var elComponentDesc = Dom.get('component_description');
    elComponentDesc.innerHTML = '';
    for (var i = 0, n = product.details.components.length; i < n; i++) {
      var component = product.details.components[i];
      if (component.name == componentName) {
        elComponentDesc.innerHTML = component.description;
        break;
      }
    }
    Dom.removeClass(elComponentDesc, 'hidden');
  },

  onVersionChange: function(version) {
    Dom.get('version').value = version;
  },

  onFileChange: function() {
    // toggle ui enabled when a file is uploaded or cleared
    var elFile = Dom.get('data');
    var elReset = Dom.get('reset_data');
    var elDescription = Dom.get('data_description');
    var filename = bugForm._getFilename();
    if (filename) {
      elReset.disabled = false;
      elDescription.value = filename;
      elDescription.disabled = false;
    } else {
      elReset.disabled = true;
      elDescription.value = '';
      elDescription.disabled = true;
    }
  },

  onFileClear: function() {
    Dom.get('data').value = '';
    this.onFileChange();
    return false;
  },

  toggleOddEven: function() {
    var rows = Dom.get('bugForm').getElementsByTagName('TR');
    var doToggle = false;
    for (var i = 0, n = rows.length; i < n; i++) {
      if (doToggle) {
        rows[i].className = rows[i].className == 'odd' ? 'even' : 'odd';
      } else {
        doToggle = rows[i].id == 'componentTR';
      }
    }
  },

  _getFilename: function() {
    var filename = Dom.get('data').value;
    if (!filename)
      return '';
    filename = filename.replace(/^.+[\\\/]/, '');
    return filename;
  },

  _mandatoryMissing: function() {
    var result = new Array();
    for (var i = 0, n = this._mandatoryFields.length; i < n; i++ ) {
      id = this._mandatoryFields[i];
      el = Dom.get(id);

      if (el.type.toString() == "checkbox") {
        value = el.checked;
      } else {
        value = el.value.replace(/^\s\s*/, '').replace(/\s\s*$/, '');
        el.value = value;
      }

      if (value == '') {
        Dom.addClass(id, 'missing');
        result.push(id);
      } else {
        Dom.removeClass(id, 'missing');
      }
    }
    return result;
  },

  validate: function() {
    
    // check mandatory fields

    var missing = bugForm._mandatoryMissing();
    if (missing.length) {
      var message = 'The following field' + 
        (missing.length == 1 ? ' is' : 's are') + ' required:\n\n';
      for (var i = 0, n = missing.length; i < n; i++ ) {
        var id = missing[i];
        if (id == 'short_desc')       message += '  Summary\n';
        if (id == 'component_select') message += '  Component\n';
        if (id == 'version_select')   message += '  Version\n';
      }
      alert(message);
      return false;
    }

    if (Dom.get('data').value && !Dom.get('data_description').value)
      Dom.get('data_description').value = bugForm._getFilename();

    Dom.get('submit').disabled = true;
    Dom.get('submit').value = 'Submitting Bug...';

    return true;
  },

  _initHelp: function(el) {
    var help_id = el.getAttribute('helpid');
    if (!el.panel) {
      if (!el.id)
        el.id = help_id + '_parent';
      el.panel = new YAHOO.widget.Panel(
        help_id, 
        { 
          width: "320px", 
          visible: false,
          close: false,
          context: [el.id, 'tl', 'tr', null, [5, 0]]
        }
      );
      el.panel.render();
      Dom.removeClass(help_id, 'hidden');
    }
  },

  showHelp: function(el) {
    this._initHelp(el);
    if (this._visibleHelpPanel)
      this._visibleHelpPanel.hide();
    el.panel.show();
    this._visibleHelpPanel = el.panel;
  },

  hideHelp: function(el) {
    if (!el.panel)
      return;
    if (this._visibleHelpPanel)
      this._visibleHelpPanel.hide();
    el.panel.hide();
    this._visibleHelpPanel = null;
  }
}

function quoteMeta(value) {
  return value.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&");
}
