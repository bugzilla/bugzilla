/* ***** BEGIN LICENSE BLOCK *****
 * Version: MPL 1.1/GPL 2.0/LGPL 2.1
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
 * The Original Code is Keyword Chooser.
 *
 * The Initial Developer of the Original Code is America Online, Inc.
 * Portions created by the Initial Developer are Copyright (C) 2004
 * Mozilla Foundation. All Rights Reserved.
 *
 * Contributor(s):
 *   Christopher A. Aillon <christopher@aillon.com> (Original Author)
 *
 * Alternatively, the contents of this file may be used under the terms of
 * either the GNU General Public License Version 2 or later (the "GPL"), or
 * the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
 * in which case the provisions of the GPL or the LGPL are applicable instead
 * of those above. If you wish to allow use of your version of this file only
 * under the terms of either the GPL or the LGPL, and not to allow others to
 * use your version of this file under the terms of the MPL, indicate your
 * decision by deleting the provisions above and replace them with the notice
 * and other provisions required by the GPL or the LGPL. If you do not delete
 * the provisions above, a recipient may use your version of this file under
 * the terms of any one of the MPL, the GPL or the LGPL.
 *
 * ***** END LICENSE BLOCK ***** */

function KeywordChooser(aParent, aChooser, aAvail, aChosen, aValidKeywords)
{
  // Initialization
  this._parent = aParent;
  this._chooser = aChooser;
  this._available = aAvail;
  this._chosen = aChosen;
  this._validKeywords = aValidKeywords;

  this.setInitialStyles();

  // Register us, our properties, and our events
  this._parent.chooser = this;
  this._chooser.chooserElement = this._parent;
}

KeywordChooser.prototype =
{
  // chooses the selected items
  choose: function()
  {
    this._swapSelected(this._available, this._chosen);
  },

  unchoose: function()
  {
    this._swapSelected(this._chosen, this._available);
  },

  positionChooser: function()
  {
    if (this._positioned) return;
    bz_overlayBelow(this._chooser, this._parent);
    this._positioned = true;
  },

  setInitialStyles: function()
  {
    this._chooser.style.display = "none";
    this._chooser.style.position = "absolute";
    this._positioned = false;
  },

  open: function()
  {
    this._chooser.style.display = "";
    this._available.style.display = "";
    this._chosen.style.display = "";
    this._parent.disabled = true;
    this.positionChooser();
  },

  ok: function()
  {
    var len = this._chosen.options.length;

    var text = "";
    for (var i = 0; i < len; i++) {
      text += this._chosen.options[i].text;
      if (i != len - 1) {
        text += ", ";
      }
    }

    this._parent.value = text;
    this._parent.title = text;

    this.close();
  },

  cancel: function()
  {
    var chosentext = this._parent.value;
    var chosenArray = new Array(); 

    if (chosentext != ""){
      chosenArray = chosentext.split(", ");
    }

    var availArray = new Array();
  
    for (var i = 0; i < this._validKeywords.length; i++) {
      if (!bz_isValueInArray(chosenArray, this._validKeywords[i])) {
        availArray[availArray.length] = this._validKeywords[i];
      }
    }

    bz_populateSelectFromArray(this._available, availArray, false, true);
    bz_populateSelectFromArray(this._chosen, chosenArray, false, true);
    this.close();
  },

  close: function()
  {
    this._chooser.style.display = "none";
    this._parent.disabled = false;
  },

  _swapSelected: function(aSource, aTarget)
  {
    var kNothingSelected = -1;
    while (aSource.selectedIndex != kNothingSelected) {
      var option = aSource.options[aSource.selectedIndex];
      aTarget.appendChild(option);
      option.selected = false;
    }
  }
};

function InitializeKeywordChooser(aValidKeywords)
{
  var keywords = document.getElementById("keywords");
  var chooser = document.getElementById("keyword-chooser");
  var avail = document.getElementById("keyword-list");
  var chosen = document.getElementById("bug-keyword-list");
  var chooserObj = new KeywordChooser(keywords, chooser, avail, chosen, aValidKeywords);
}
