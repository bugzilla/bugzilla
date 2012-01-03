/* ***** BEGIN LICENSE BLOCK *****
 * Version: MPL 1.1
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
 * for the specific language governing rights and limitations under the
 * License.
 *
 * The Original Code is the GuidedBugEntry Bugzilla Extension.
 *
 * The Initial Developer of the Original Code is
 * the Mozilla Foundation.
 * Portions created by the Initial Developer are Copyright (C) 2011
 * the Initial Developer. All Rights Reserved.
 *
 * Contributor(s):
 *   Byron Jones <glob@mozilla.com>
 *
 * ***** END LICENSE BLOCK ***** */

/* Product-specifc configuration for guided bug entry
 *
 * related: array of product names which will also be searched for duplicates
 * version: function which returns a version (eg. detected from UserAgent)
 * support: string which is displayed at the top of the duplicates page
 * secgroup: the group to place confidential bugs into
 * defaultComponent: the default compoent to select.  Defaults to 'General'
 * noComponentSelection: when true, the default component will always be
 *     used.  Defaults to 'false';
 * detectPlatform: when true the platform and op_sys will be set from the
 *     browser's user agent.  when false, these will be set to All
 */

var products = {

  "Firefox": {
    related: [ "Core", "Toolkit" ],
    version: function() {
      var re = /Firefox\/(\d+)\.(\d+)/i;
      var match = re.exec(navigator.userAgent);
      if (match) {
        var maj = match[1];
        var min = match[2];
        if (maj * 1 >= 5) {
          return maj + " Branch";
        } else {
          return maj + "." + min + " Branch";
        }
      } else {
        return false;
      }
    },
    defaultComponent: "Untriaged",
    noComponentSelection: true,
    detectPlatform: true,
    support:
      'If you are new to Firefox or Bugzilla, please consider checking ' +
      '<a href="http://support.mozilla.com/">' +
      '<img src="extensions/GuidedBugEntry/web/images/sumo.png" width="16" height="16" align="absmiddle">' +
      ' <b>Firefox Help</b></a> instead of creating a bug.'
  },

  "Fennec": {
    related: [ "Fennec Native", "Core", "Toolkit" ],
    detectPlatform: true,
    support:
      'If you are new to Firefox or Bugzilla, please consider checking ' +
      '<a href="http://support.mozilla.com/">' +
      '<img src="extensions/GuidedBugEntry/web/images/sumo.png" width="16" height="16" align="absmiddle">' +
      ' <b>Firefox Help</b></a> instead of creating a bug.'
  },

  "Fennec Native": {
    related: [ "Fennec", "Core", "Toolkit" ],
    detectPlatform: true,
    support:
      'If you are new to Firefox or Bugzilla, please consider checking ' +
      '<a href="http://support.mozilla.com/">' +
      '<img src="extensions/GuidedBugEntry/web/images/sumo.png" width="16" height="16" align="absmiddle">' +
      ' <b>Firefox Help</b></a> instead of creating a bug.'
  },

  "SeaMonkey": {
    related: [ "Core", "Toolkit" ],
    detectPlatform: true,
    version: function() {
      var re = /SeaMonkey\/(\d+)\.(\d+)/i;
      var match = re.exec(navigator.userAgent);
      if (match) {
        var maj = match[1];
        var min = match[2];
        return "SeaMonkey " + maj + "." + min + " Branch";
      } else {
        return false;
      }
    }
  },

  "Camino": {
    related: [ "Core", "Toolkit" ],
    detectPlatform: true
  },

  "Core": {
    detectPlatform: true
  },

  "Thunderbird": {
    related: [ "Core", "Toolkit", "MailNews Core" ],
    detectPlatform: true
  },

  "Penelope": {
    related: [ "Core", "Toolkit", "MailNews Core" ]
  },

  "Bugzilla": {
    support:
      'Please use <a href="http://landfill.bugzilla.org/">Bugzilla Landfill</a> to file "test bugs".'
  },

  "bugzilla.mozilla.org": {
    related: [ "Bugzilla" ],
    support:
      'Please use <a href="http://landfill.bugzilla.org/">Bugzilla Landfill</a> to file "test bugs".'
  }
}
