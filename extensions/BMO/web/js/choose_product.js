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
    dataSource : null,
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
      return YAHOO.lang.JSON.stringify(json_object);
    },
    resultListFormat : function(oResultData, enteredText, sResultMatch) {
        var url  = "enter_bug.cgi?product=" + encodeURIComponent(oResultData[0]) +
                   "&component=" +  encodeURIComponent(oResultData[1]);
        if (YAHOO.bugzilla.prodCompSearch.format) {
            url = url + "&format=" + encodeURIComponent(YAHOO.bugzilla.prodCompSearch.format);
        }
        return ("<a href=\"" + url + "\"><b>" +
                _escapeHTML(oResultData[0]) + "</b> :: " + 
                _escapeHTML(oResultData[1]) + "</a>");
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
    init : function( field, container, format) {
        if( this.dataSource == null ){
            this.init_ds();
        }
        this.format = format;
        var prodCompSearch = new YAHOO.widget.AutoComplete(field, container, this.dataSource);
        prodCompSearch.generateRequest = this.generateRequest;
        prodCompSearch.formatResult = this.resultListFormat;
        prodCompSearch.minQueryLength = 3;
        prodCompSearch.autoHighlight = false;
        prodCompSearch.queryDelay = 0.05;
        prodCompSearch.useIFrame = true;
        prodCompSearch.maxResultsDisplayed = 25;
        prodCompSearch.suppressInputUpdate = true;
        prodCompSearch.textboxFocusEvent.subscribe(function () {
            var input = YAHOO.util.Dom.get(field);
            if (input.value && input.value.length > 3) {
                this.sendQuery(input.value);
            }
        });
    }
}
