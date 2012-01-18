/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var Dom = YAHOO.util.Dom;
var flagEl;
var productEl;
var trackingEl;
var selectedFields;

// events

function onFieldToggle(cbEl, id) {
  if (cbEl.checked) {
    Dom.removeClass('field_' + id + '_td', 'disabled');
    selectedFields['field_' + id] = id;
  } else {
    Dom.addClass('field_' + id + '_td', 'disabled');
    selectedFields['field_' + id] = false;
  }
  Dom.get('field_' + id + '_select').disabled = !cbEl.checked;
  serialiseForm();
}

function onProductChange() {
  var product = productEl.value;
  var productData = product == '0' ? getFlagByName(flagEl.value) : getProductById(product);
  var html = '';
  selectedFields = new Array();

  if (productData) {
    // update status fields
    html = '<table>';
    for(var i = 0, l = productData.fields.length; i < l; i++) {
      var field = getFieldById(productData.fields[i]);
      selectedFields['field_' + field.id] = false;
      html += '<tr>' +
              '<td>' +
                '<input type="checkbox" id="field_' + field.id + '_cb" ' +
                        'onClick="onFieldToggle(this,' + field.id + ')">' +
              '</td>' +
              '<td class="disabled" id="field_' + field.id + '_td">' + 
                '<label for="field_' + field.id + '_cb">' +
                YAHOO.lang.escapeHTML(field.name) + ':</label>' +
              '</td>' +
              '<td>' +
                '<select disabled id="field_' + field.id + '_select">' +
                  '<option value="+">fixed</option>' +
                  '<option value="-">not fixed</option>' +
                '</select>' +
              '</td>' +
              '</tr>';
    }
    html += '</table>';
  }
  trackingEl.innerHTML = html;
  serialiseForm();
}

function onFlagChange() {
  var flag = flagEl.value;
  var flagData = getFlagByName(flag);
  productEl.options.length = 0;

  if (flagData) {
    // update product select
    var currentProduct = productEl.value;
    productEl.options[0] = new Option('(Any Product)', '0');
    for(var i = 0, l = flagData.products.length; i < l; i++) {
      var product = getProductById(flagData.products[i]);
      var n = productEl.length;
      productEl.options[n] = new Option(product.name, product.id);
      productEl.options[n].selected = product.id == currentProduct;
    }
  }
  onProductChange();
}

// form

function selectAllFields() {
  for(var i = 0, l = fields_data.length; i < l; i++) {
    var cb = Dom.get('field_' + fields_data[i].id + '_cb');
    cb.checked = true;
    onFieldToggle(cb, fields_data[i].id);
  }
  serialiseForm();
}

function selectNoFields() {
  for(var i = 0, l = fields_data.length; i < l; i++) {
    var cb = Dom.get('field_' + fields_data[i].id + '_cb');
    cb.checked = false;
    onFieldToggle(cb, fields_data[i].id);
  }
  serialiseForm();
}

function invertFields() {
  for(var i = 0, l = fields_data.length; i < l; i++) {
    var el = Dom.get('field_' + fields_data[i].id + '_select');
    if (el.value == '+') {
      el.options[1].selected = true;
    } else {
      el.options[0].selected = true;
    }
  }
  serialiseForm();
}

function onFormSubmit() {
  serialiseForm();
  return true;
}

function onFormReset() {
  deserialiseForm('');
}

function serialiseForm() {
  var q = flagEl.value + ':' +
          Dom.get('flag_value').value + ':' +
          Dom.get('range').value + ':' +
          productEl.value + ':' +
          Dom.get('op').value + ':';

  for(var id in selectedFields) {
    if (selectedFields[id]) {
      q += selectedFields[id] + Dom.get(id + '_select').value + ':';
    }
  }

  Dom.get('q').value = q;
  Dom.get('bookmark').href = 'page.cgi?id=release_tracking_report.html&q=' +
                             encodeURIComponent(q);
}

function deserialiseForm(q) {
  var parts = q.split(/:/);
  selectValue(flagEl, parts[0]);
  onFlagChange();
  selectValue(Dom.get('flag_value'), parts[1]);
  selectValue(Dom.get('range'), parts[2]);
  selectValue(productEl, parts[3]);
  onProductChange();
  selectValue(Dom.get('op'), parts[4]);
  for(var i = 5, l = parts.length; i < l; i++) {
    var part = parts[i];
    if (part.length) {
      var value = part.substr(part.length - 1, 1);
      var id = part.substr(0, part.length - 1);
      var cb = Dom.get('field_' + id + '_cb');
      cb.checked = true;
      onFieldToggle(cb, id);
      selectValue(Dom.get('field_' + id + '_select'), value);
    }
  }
  serialiseForm();
}

// utils

YAHOO.util.Event.onDOMReady(function() {
  flagEl = Dom.get('flag');
  productEl = Dom.get('product');
  trackingEl = Dom.get('tracking_span');
  onFlagChange();
  deserialiseForm(default_query);
});

function getFlagByName(name) {
  for(var i = 0, l = flags_data.length; i < l; i++) {
    if (flags_data[i].name == name)
      return flags_data[i];
  }
}

function getProductById(id) {
  for(var i = 0, l = products_data.length; i < l; i++) {
    if (products_data[i].id == id)
      return products_data[i];
  }
}

function getFieldById(id) {
  for(var i = 0, l = fields_data.length; i < l; i++) {
    if (fields_data[i].id == id)
      return fields_data[i];
  }
}

function selectValue(el, value) {
  for(var i = 0, l = el.options.length; i < l; i++) {
    if (el.options[i].value == value) {
      el.options[i].selected = true;
      return;
    }
  }
  el.options[0].selected = true;
}
