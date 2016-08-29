/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

var DE = {
  formUpdate: function () {
    var sections = {
      developer_event_warning: false,
      code_of_conduct_warning: false,
      mozilla_attending_warning: false,
      mozillian_profile_url_section: false,
      mozilla_attending_list_section: false,
      code_of_conduct_url_section: false,
      speaker_needed_detail_section: false,
      previous_event_details_section: false
    };
    var commit_disabled = false;

    if (fieldValue('developer_event') == 'No') {
      commit_disabled = true;
      sections.developer_event_warning = true;
    }

    if (fieldValue('mozilla_attending') == 'No') {
      sections.mozilla_attending_warning = true;
    }
    else if (fieldValue('mozilla_attending') == 'Yes') {
      sections.mozilla_attending_list_section = true;
    }

    if (fieldValue('code_of_conduct') == 'No') {
      commit_disabled = true;
      sections.code_of_conduct_warning = true;
    }
    else if (fieldValue('code_of_conduct') == 'Yes') {
      sections.code_of_conduct_url_section = true;
    }

    if (fieldValue('vouched_mozillian') == 'Yes') {
      sections.mozillian_profile_url_section = true;
    }

    if (fieldValue('previous_event') == 'Yes') {
      sections.previous_event_details_section = true;
    }

    if (fieldValue('speaker_needed') == 'Yes') {
      sections.speaker_needed_detail_section = true;
    }

    for (section in sections) {
      if (sections[section]) {
        DE.removeClass(document.getElementById(section),
                               'bz_default_hidden');
      }
      else {
        DE.addClass(document.getElementById(section),
                            'bz_default_hidden');
      }
    }
    YAHOO.util.Dom.get('commit').disabled = commit_disabled;
  },
  focusOther: function (id, other_id) {
    var cb = document.getElementById(id);
    var input = document.getElementById(other_id);
    input.disabled = !cb.checked;
    if (cb.checked) input.focus();
  },
  onSubmit: function (ev) {
    var alert_text = '';
    // Required fields check
    var required_text_fields = {
      'name' : 'Please enter your name.',
      'email' : 'Please enter your email address.',
      'role' : 'Please enter your role.',
      'event' : 'Please enter the event name.',
      'start_date' : 'Please enter the event start date.',
      'end_date' : 'Please enter the event end date.',
      'location' : 'Please enter a location description for the event.',
      'attendees' : 'Please enter number of expected attendees.',
      'audience' : 'Please enter the intended audience for the event.',
      'desc' : 'Please enter a description of the event.',
    };

    var required_selects = {
      'vouched_mozillian' : 'Please select if you are a vouched mozillian.',
      'developer_event' : 'Please select if this is a developer event.',
      'mozilla_attending' : 'Please select if Mozilla is attending the event.',
      'code_of_conduct' : 'Please select if the event has a code of conduct.',
      'event_location' : 'Please a location for the event.',
      'previous_event' : 'Please select if Mozilla has sponsored this event before.',
    };

    if (fieldValue('vouched_mozillian') == 'Yes')
      required_text_fields['mozillian_profile_url']
        = 'Please enter your mozillian profile url.';
    if (fieldValue('mozilla_attending') == 'Yes')
      required_text_fields['mozilla_attending_list']
        = 'Please enter a list of Mozilla persons attending the event.';
    if (fieldValue('code_of_conduct') == 'Yes')
      required_text_fields['code_of_conduct_url']
        = 'Please enter a code of conduct url.';
    if (fieldValue('previous_event') == 'Yes') {
      required_text_fields['previous_event_year']
        = 'Please select a year for the previous sponsored event.';
      required_text_fields['previous_event_name']
        = 'Please enter a name for the previous sponsored event.';
    }

    var relevant_products = [
      'product_fx',
      'product_encryption',
      'product_web_asm',
      'product_rust',
      'product_servo',
      'product_webvr',
      'product_fow',
      'product_devtools',
      'product_other',
    ];
    var found = 0;
    for (var i = 0, l = relevant_products.length; i < l; i ++) {
      if (isChecked(relevant_products[i])) found = 1;
    }
    if (!found)
      alert_text += "Please check one or more relevant products.\n";
    if (isChecked('product_other'))
      required_text_fields['product_other_text']
        = 'Please enter a value for other relevant product.';

    var request_types = [
      'request_keynote',
      'request_talk',
      'request_workshop',
      'request_sponsorship',
      'request_other'
    ];
    found = 0;
    for (var i = 0, l = request_types.length; i < l; i ++) {
      if (isChecked(request_types[i])) found = 1;
    }
    if (!found)
      alert_text += "Please check one or more items being requested of Mozilla.\n";
    if (isChecked('request_other'))
      required_text_fields['request_other_text']
        = 'Please enter a value for other item being requested.';

    for (field in required_text_fields) {
      if (!isFilledOut(field))
        alert_text += required_text_fields[field] + "\n";
    }
    for (field in required_selects) {
      if (!fieldValue(field))
        alert_text += required_selects[field] + "\n";
    }
    if (alert_text != '') {
      alert(alert_text);
      YAHOO.util.Event.stopEvent(ev);
    }

    // Whiteboard value
    var wb = '';
    var location_wb_map = {
      'Africa' : 'africa',
      'Asia' : 'asia',
      'Australia' : 'australia',
      'Europe' : 'europe',
      'North America' : 'north-america',
      'Central / South America' : 'central-south-america',
      'Multiple' : 'multiple',
      'Online only' : 'online',
    };
    wb += '[location:' + location_wb_map[fieldValue('event_location')] + '] ';

    var request_items = [];
    if (document.getElementById('request_keynote').checked)
      request_items.push('keynote');
    if (document.getElementById('request_talk').checked)
      request_items.push('talk');
    if (document.getElementById('request_workshop').checked)
      request_items.push('workshop');
    if (document.getElementById('request_sponsorship').checked)
      request_items.push('sponsorship');
    if (document.getElementById('request_other').checked)
      request_items.push('other');
    wb += '[requesting:' + request_items.join(',') + '] ';

    var product_items = [];
    if (document.getElementById('product_fx').checked)
      product_items.push('firefox-web-browser');
    if (document.getElementById('product_encryption').checked)
      product_items.push('encryption');
    if (document.getElementById('product_web_asm').checked)
      product_items.push('web-assembly-or-platform');
    if (document.getElementById('product_rust').checked)
      product_items.push('servo');
    if (document.getElementById('product_servo').checked)
      product_items.push('rust');
    if (document.getElementById('product_webvr').checked)
      product_items.push('webvr');
    if (document.getElementById('product_fow').checked)
      product_items.push('open-web');
    if (document.getElementById('product_devtools').checked)
      product_items.push('developer-tools');
    if (document.getElementById('product_other').checked)
      product_items.push('other');
    wb += '[products:' + product_items.join(',') + '] ';

    if (fieldValue('developer_event') == 'Yes')
      wb += '[developer-event:true] ';
    var mozilla_attending = fieldValue('mozilla_attending') == 'Yes' ? 'true' : 'false';
    wb += '[mozilla-already-attending:' + mozilla_attending + '] ';
    var vouched = fieldValue('vouched_mozillian') == 'Yes' ? 'true' : 'false';
    wb += '[requested-by-mozillian:' + vouched + '] ';
    if (fieldValue('code_of_conduct') == 'Yes')
      wb += '[code-of-conduct:true] ';
    var previous_event = fieldValue('previous_event') == 'Yes' ? 'true' : 'false';
    wb += '[past-sponsorship:' + previous_event + '] ';
    var needs_speaker = fieldValue('speaker_needed') == 'Yes' ? 'true' : 'false';
    wb += '[needs-speaker:' + needs_speaker + '] ';
    var sponsor_booth = fieldValue('sponsor_booth') == 'Yes' ? 'true' : 'false';
    wb += '[option-to-sponsor-booth:' + sponsor_booth + '] ';
    wb += '[expected-attendees:' + fieldValue('attendees') + '] ';
    var prospectus = fieldValue('data') ? 'true' : 'false';
    wb += '[prospectus:' + prospectus + '] ';
    document.getElementById('status_whiteboard').value = wb.replace(/ $/, '');

    var summary = document.getElementById('event').value + ', ' + DE.long_start_date();
    var loc = document.getElementById('location').value;
    if (loc)
      summary = summary + ' (' + loc + ')';
    document.getElementById('short_desc').value = summary;
    document.getElementById('bug_file_loc').value = document.getElementById('link').value;
    document.getElementById('cf_due_date').value = document.getElementById('start_date').value;
  },
  long_start_date: function () {
    var ymd = document.getElementById('start_date').value.split('-');
    if (ymd.length != 3)
      return '';
    var month = YAHOO.bugzilla.calendar_start_date.cfg.getProperty('MONTHS_LONG')[ymd[1] - 1];
    return month + ' ' + ymd[0];
  },
  hasClass: function (element, class_name) {
    return element.className.match(new RegExp('(\\s|^)' + class_name + '(\\s|$)'));
  },
  addClass: function (element, class_name) {
    if (!DE.hasClass(element, class_name))
      element.className += " " + class_name;
  },
  removeClass: function (element, class_name) {
    if (DE.hasClass(element, class_name)) {
        var reg = new RegExp('(\\s|^)' + class_name + '(\\s|$)');
        element.className = element.className.replace(reg,' ');
    }
  },
  init: function() {
    YAHOO.util.Event.on('dev_form', 'submit', DE.onSubmit);
    YAHOO.util.Event.on('product_other', 'change', function () {
      DE.focusOther('product_other', 'product_other_text');
    });
    YAHOO.util.Event.on('request_other', 'change', function () {
      DE.focusOther('request_other', 'request_other_text');
    });
    var select_inputs = [
      'developer_event',
      'code_of_conduct',
      'vouched_mozillian',
      'mozilla_attending',
      'speaker_needed',
      'previous_event'
    ];
    for (var i = 0, l = select_inputs.length; i < l; i++) {
      YAHOO.util.Event.on(select_inputs[i], 'change', DE.formUpdate);
    }
    DE.formUpdate();
    createCalendar('start_date');
    createCalendar('end_date');
  }
};
YAHOO.util.Event.onDOMReady(DE.init);
