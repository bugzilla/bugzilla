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
 * The Original Code is the Cross Platform JavaScript Utility Library.
 *
 * The Initial Developer of the Original Code is
 * Everything Solved.
 * Portions created by the Initial Developer are Copyright (C) 2007
 * the Initial Developer. All Rights Reserved.
 *
 * Contributor(s):
 *   Max Kanat-Alexander <mkanat@bugzilla.org>
 *   Christopher A. Aillon <christopher@aillon.com>
 *
 * ***** END LICENSE BLOCK ***** */

/**
 * Locate where an element is on the page, x-wise.
 *
 * @param  obj Element of which location to return.
 * @return     Current position of the element relative to the left of the
 *             page window. Measured in pixels.
 */
function bz_findPosX(obj)
{
    var curleft = 0;

    if (obj.offsetParent) {
        while (obj) {
            curleft += obj.offsetLeft;
            obj = obj.offsetParent;
        }
    }
    else if (obj.x) {
        curleft += obj.x;
    }

    return curleft;
}

/**
 * Locate where an element is on the page, y-wise.
 *
 * @param  obj Element of which location to return.
 * @return     Current position of the element relative to the top of the
 *             page window. Measured in pixels.
 */
function bz_findPosY(obj)
{
    var curtop = 0;

    if (obj.offsetParent) {
        while (obj) {
            curtop += obj.offsetTop;
            obj = obj.offsetParent;
        }
    }
    else if (obj.y) {
        curtop += obj.y;
    }

    return curtop;
}

/**
 * Get the full height of an element, even if it's larger than the browser
 * window.
 *
 * @param  fromObj Element of which height to return.
 * @return         Current height of the element. Measured in pixels.
 */
function bz_getFullHeight(fromObj)
{
    var scrollY;

    // All but Mac IE
    if (fromObj.scrollHeight > fromObj.offsetHeight) {
        scrollY = fromObj.scrollHeight;
    // Mac IE
    }  else {
        scrollY = fromObj.offsetHeight;
    }

    return scrollY;
}

/**
 * Get the full width of an element, even if it's larger than the browser
 * window.
 *
 * @param  fromObj Element of which width to return.
 * @return         Current width of the element. Measured in pixels.
 */
function bz_getFullWidth(fromObj)
{
    var scrollX;

    // All but Mac IE
    if (fromObj.scrollWidth > fromObj.offsetWidth) {
        scrollX = fromObj.scrollWidth;
    // Mac IE
    }  else {
        scrollX = fromObj.offsetWidth;
    }

    return scrollX;
}

/**
 * Causes a block to appear directly underneath another block,
 * overlaying anything below it.
 * 
 * @param item   The block that you want to move.
 * @param parent The block that it goes on top of.
 * @return nothing
 */
function bz_overlayBelow(item, parent) {
    var elemY = bz_findPosY(parent);
    var elemX = bz_findPosX(parent);
    var elemH = parent.offsetHeight;

    item.style.position = 'absolute';
    item.style.left = elemX + "px";
    item.style.top = elemY + elemH + 1 + "px";
}

/**
 * Create wanted options in a select form control.
 *
 * @param  aSelect        Select form control to manipulate.
 * @param  aValue         Value attribute of the new option element.
 * @param  aTextValue     Value of a text node appended to the new option
 *                        element.
 * @param  aOwnerDocument Owner document of the new option element. If not
 *                        specified then "document" will be used.
 * @return                Created option element.
 */
function bz_createOptionInSelect(aSelect, aValue, aTextValue, aOwnerDocument)
{
  if (!aOwnerDocument) {
    aOwnerDocument = document;
  }

  var myOption = aOwnerDocument.createElement("option");
  myOption.setAttribute("value", aValue);

  var myTextNode = aOwnerDocument.createTextNode(aTextValue)
  myOption.appendChild(myTextNode);

  aSelect.appendChild(myOption);

  return myOption;
}

/**
 * Clears all options from a select form control.
 *
 * @param  aElm       Select form control of which options to clear.
 * @param  aSkipFirst Boolean; true to skip (not clear) first option in the
 *                    select and false to remove all options.
 */
function bz_clearOptions(aElm, aSkipFirst)
{
  var start = 0;

  // Skip the first element? (for 'Choose One' type foo)
  if (aSkipFirst) {
    start = 1;
  }

  var length = aElm.options.length;

  for (var run = start; run < length; run++) {
    aElm.removeChild(aElm.options[start]);
  }
}

/**
 * Takes an array and moves all the values to an select.
 *
 * @param aSelect         Select form control to populate. Will be cleared
 *                        before array values are created in it.
 * @param aArray          Array with values to populate select with.
 * @param aSkipFirst      Boolean; true to skip (not touch) first option in the
 *                        select and false to remove all options.
 * @param aUseNameAsValue Boolean; true if name is used as value and false if
 *                        not.
 */
function bz_populateSelectFromArray(aSelect, aArray, aSkipFirst, aUseNameAsValue)
{
  // Clear the field
  bz_clearOptions(aSelect, aSkipFirst);

  for (var run = 0; run < aArray.length; run++) {
    if (aUseNameAsValue) {
      bz_createOptionInSelect(aSelect, aArray[run], aArray[run]);
    } else {
      bz_createOptionInSelect(aSelect, aArray[run][0], aArray[run][0]);
    }
  }
}

/**
 * Checks if a specified value is in the specified array.
 *
 * @param  aArray Array to search for the value.
 * @param  aValue Value to search from the array.
 * @return        Boolean; true if value is found in the array and false if not.
 */
function bz_isValueInArray(aArray, aValue)
{
  var run = 0;
  var len = aArray.length;

  for ( ; run < len; run++) {
    if (aArray[run] == aValue) {
      return true;
    }
  }

  return false;
}
