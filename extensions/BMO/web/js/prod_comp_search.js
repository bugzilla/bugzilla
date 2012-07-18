/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. 
 */

YAHOO.bugzilla.prodCompSearch = {
    counter : 0,
    format  : '',
    cloned_bug_id : '',
    dataSource : null,
    autoComplete: null,
    generateRequest : function (enteredText) {
      YAHOO.bugzilla.prodCompSearch.counter = YAHOO.bugzilla.prodCompSearch.counter + 1;
      YAHOO.util.Connect.setDefaultPostHeader('application/json', true);
      var json_object = {
          method : "BMO.prod_comp_search",
          id : YAHOO.bugzilla.prodCompSearch.counter,
          params : [ {
            search : decodeURIComponent(enteredText)
          } ]
      };
      YAHOO.util.Dom.removeClass('prod_comp_throbber', 'hidden');
      return YAHOO.lang.JSON.stringify(json_object);
    },
    resultListFormat : function(oResultData, enteredText, sResultMatch) {
        return YAHOO.lang.escapeHTML(oResultData[0]) + " :: " + 
               YAHOO.lang.escapeHTML(oResultData[1]);
    },
    init_ds : function(){
        this.dataSource = new YAHOO.util.XHRDataSource("jsonrpc.cgi");
        this.dataSource.connTimeout = 30000;
        this.dataSource.connMethodPost = true;
        this.dataSource.connXhrMode = "cancelStaleRequests";
        this.dataSource.maxCacheEntries = 5;
        this.dataSource.responseType = YAHOO.util.DataSource.TYPE_JSON;
        this.dataSource.responseSchema = {
            resultsList : "result.products",
            metaFields : { error: "error", jsonRpcId: "id"},
            fields : [ "product", "component" ]
        };
    },
    init : function(field, container, format, cloned_bug_id) {
        if (this.dataSource == null)
            this.init_ds();
        this.format = format;
        this.cloned_bug_id = cloned_bug_id;
        this.autoComplete = new YAHOO.widget.AutoComplete(field, container, this.dataSource);
        this.autoComplete.generateRequest = this.generateRequest;
        this.autoComplete.formatResult = this.resultListFormat;
        this.autoComplete.minQueryLength = 3;
        this.autoComplete.autoHighlight = false;
        this.autoComplete.queryDelay = 0.05;
        this.autoComplete.useIFrame = true;
        this.autoComplete.maxResultsDisplayed = 25;
        this.autoComplete.suppressInputUpdate = true;
        this.autoComplete.doBeforeLoadData = function(sQuery, oResponse, oPayload) {
            YAHOO.util.Dom.addClass('prod_comp_throbber', 'hidden');
            return true;
        };
        this.autoComplete.textboxFocusEvent.subscribe(function () {
            var input = YAHOO.util.Dom.get(field);
            if (input.value && input.value.length > 3) {
                this.sendQuery(input.value);
            }
        });
        this.autoComplete.itemSelectEvent.subscribe(function (e, args) {
            var oData = args[2];
            var url  = "enter_bug.cgi?product=" + encodeURIComponent(oData[0]) +
                       "&component=" +  encodeURIComponent(oData[1]);
            var format = YAHOO.bugzilla.prodCompSearch.format;
            if (format)
                url += "&format=" + encodeURIComponent(format);
            var cloned_bug_id = YAHOO.bugzilla.prodCompSearch.cloned_bug_id;
            if (cloned_bug_id)
                url += "&cloned_bug_id=" + encodeURIComponent(cloned_bug_id);
            window.location.href = url;
        });
        this.autoComplete.dataReturnEvent.subscribe(function(type, args) {
          args[0].autoHighlight = args[2].length == 1;
        });
    }
}
