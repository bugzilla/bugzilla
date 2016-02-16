/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var flagEl;
var productEl;
var trackingEl;
var selectedFields;

// events

function onFieldToggle(cbEl, id) {
  if (cbEl.checked) {
    $('#field_' + id + '_td').removeClass('disabled');
    selectedFields['field_' + id] = id;
  } else {
    $('#field_' + id + '_td').addClass('disabled');
    selectedFields['field_' + id] = false;
  }
  $('#field_' + id + '_select').attr('disabled', !cbEl.checked);
  serialiseForm();
}

function onProductChange() {
  var product = productEl.value;
  var productData = product == '0' ? getFlagByName(flagEl.value) : getProductById(product);
  var html = '';
  selectedFields = [];

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
                field.desc.htmlEncode() + ':</label>' +
              '</td>' +
              '<td>' +
                '<select disabled id="field_' + field.id + '_select" ' +
                        'onChange="onFieldToggle($(\'#field_' + field.id + '_cb\')[0],' + field.id + ')">' +
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
    var cb = $('#field_' + fields_data[i].id + '_cb')[0];
    if (!cb) continue;
    cb.checked = true;
    onFieldToggle(cb, fields_data[i].id);
  }
  serialiseForm();
}

function selectNoFields() {
  for(var i = 0, l = fields_data.length; i < l; i++) {
    var cb = $('#field_' + fields_data[i].id + '_cb')[0];
    if (!cb) continue;
    cb.checked = false;
    onFieldToggle(cb, fields_data[i].id);
  }
  serialiseForm();
}

function invertFields() {
  for(var i = 0, l = fields_data.length; i < l; i++) {
    var el = $('#field_' + fields_data[i].id + '_select')[0];
    if (!el) continue;
    if (el.value == '+') {
      el.options[1].selected = true;
    } else {
      el.options[0].selected = true;
    }
  }
  serialiseForm();
}

function onFormSubmit() {
  if ($('#is_custom').is(':checked') && (!$('#from').val() || !$('#to').val())) {
    alert('You must enter both the start and end dates.');
    return false;
  }
  serialiseForm();
  return true;
}

function onFormReset() {
  deserialiseForm('');
}

function selectRangeType() {
  if ($('#is_custom').is(':checked')) {
    $('#custom_range').show();
    $('#fixed_range').hide();
  }
  else {
    $('#custom_range').hide();
    $('#fixed_range').show();
  }
  serialiseForm();
}

function serialiseForm() {
  var q = flagEl.value + ':' +
          $('#flag_value').val() + ':';
  if ($('#is_custom').is(':checked')) {
    var from = $('#from').val();
    var to = $('#to').val();
    q = q + from.replace(/-/g, '') +
            '-' + to.replace(/-/g, '');
  }
  else {
    q = q + $('#range').val();
  }
  q = q + ':' + productEl.value + ':' +
      $('#op').val() + ':';
  for(var id in selectedFields) {
    if (selectedFields[id]) {
      q += selectedFields[id] + $('#' + id + '_select').val() + ':';
    }
  }

  $('#q').val(q);
  var is_custom = $('#is_custom').is(':checked') ? 1 : 0;
  $('#bookmark').attr('href', 'page.cgi?id=release_tracking_report.html&is_custom=' +
                               is_custom + '&q=' + encodeURIComponent(q));
}

function deserialiseForm(q) {
  var parts = q.split(/:/);
  selectValue(flagEl, parts[0]);
  onFlagChange();
  selectValue($('#flag_value')[0], parts[1]);
  if (!selectValue($('#range')[0], parts[2]) && parts[2]) {
    var match = parts[2].match(/^(\d\d\d\d)(\d\d)(\d\d)-(\d\d\d\d)(\d\d)(\d\d)$/);
    if (match) {
      $('#from').val(match[1] + '-' + match[2] + '-' + match[3]);
      $('#to').val(match[4] + '-' + match[5] + '-' + match[6]);
    }
  }
  selectValue(productEl, parts[3]);
  onProductChange();
  selectValue($('#op')[0], parts[4]);
  for(var i = 5, l = parts.length; i < l; i++) {
    var part = parts[i];
    if (part.length) {
      var value = part.substr(part.length - 1, 1);
      var id = part.substr(0, part.length - 1);
      var cb = $('#field_' + id + '_cb')[0];
      cb.checked = true;
      onFieldToggle(cb, id);
      selectValue($('#field_' + id + '_select')[0], value);
    }
  }
  serialiseForm();
}

// utils

$().ready(function() {
  flagEl = $('#flag')[0];
  productEl = $('#product')[0];
  trackingEl = $('#tracking_span')[0];
  onFlagChange();
  deserialiseForm(default_query);
  selectRangeType();
});

$(function() {
  $('.date_field').datetimepicker({
    format: 'Y-m-d',
    datepicker: true,
    timepicker: false,
    scrollInput: false,
    lazyInit: false,
    closeOnDateSelect: true
  });
  $('.date_field-img')
    .click(function(event) {
      var id = $(event.target).attr('id').replace(/-img$/, '');
      $('#' + id).datetimepicker('show');
    });
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
      return true;
    }
  }
  el.options[0].selected = true;
  return false;
}
