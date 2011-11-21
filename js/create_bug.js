function toggleAdvancedFields() {
  TUI_toggle_class('expert_fields');
  var elements = YAHOO.util.Dom.getElementsByClassName('expert_fields');   
  if (YAHOO.util.Dom.hasClass(elements[0], TUI_HIDDEN_CLASS)) {
    handleWantsBugFlags(false);
  }
}

function handleWantsBugFlags(wants) {
  if (wants) {
    hideElementById('bug_flags_false');
    showElementById('bug_flags_true');
  }
  else {
    showElementById('bug_flags_false');
    hideElementById('bug_flags_true');
    clearBugFlagFields();
  }
}

function clearBugFlagFields() {
  var flags_table;
  flags_table = document.getElementById('bug_flags');
  if (flags_table) {
    var selects = flags_table.getElementsByTagName('select');
    for (var i = 0, il = selects.length; i < il; i++) {
      if (selects[i].value != 'X') {
        selects[i].value = 'X';
        toggleRequesteeField(selects[i]);
      }
    }
  }
  flags_table = document.getElementById('bug_tracking_flags');
  if (flags_table) {
    var selects = flags_table.getElementsByTagName('select');
    for (var i = 0, il = selects.length; i < il; i++) {
      selects[i].value = '---';
    }
  }
}

YAHOO.util.Event.onDOMReady(function() {
  function set_width(id, width) {
    var el = document.getElementById(id);
    if (!el) return;
    el.style.width = width + 'px';
  }

  // force field widths
  
  var width = document.getElementById('short_desc').clientWidth + 'px';
  var el;

  el = document.getElementById('comment');
  el.style.width = width;

  el = document.getElementById('cf_crash_signature');
  if (el) el.style.width = width;

  // show the bug flags if a flag is set

  var flag_set = false;
  var flags_table;
  flags_table = document.getElementById('bug_flags');
  if (flags_table) {
    var selects = flags_table.getElementsByTagName('select');
    for (var i = 0, il = selects.length; i < il; i++) {
      if (selects[i].value != 'X') {
        flag_set = true;
        break;
      }
    }
  }
  if (!flag_set) {
    flags_table = document.getElementById('bug_tracking_flags');
    if (flags_table) {
      var selects = flags_table.getElementsByTagName('select');
      for (var i = 0, il = selects.length; i < il; i++) {
        if (selects[i].value != '---') {
          flag_set = true;
          break;
        }
      }
    }
  }

  if (flag_set) {
    hideElementById('bug_flags_false');
    showElementById('bug_flags_true');
  } else {
    hideElementById('bug_flags_true');
    showElementById('bug_flags_false');
  }
  showElementById('btn_no_bug_flags')
});

function take_bug(user) {
  var el = Dom.get('assigned_to');
  el.value = user;
  el.focus();
  el.select();
  assignee_change(user);
  return false;
}

function assignee_change(user) {
  var el = Dom.get('take_bug');
  if (!el) return;
  el.style.display = Dom.get('assigned_to').value == user ? 'none' : '';
}

function init_take_handler(user) {
  YAHOO.util.Event.addListener(
    'assigned_to', 'change', function() { assignee_change(user); });
  assignee_change(user);
}
