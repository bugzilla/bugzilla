(function() {
  var action = document.getElementById('donate_action') ||
    document.getElementById('donate_banner_pref');
  var field = document.getElementById('donate_banner_date_field') ||
    document.getElementById('donate_date_row');
  var date = document.getElementById('donate_banner_reminder_date');

  if (!action || !field || !date) {
    return;
  }

  function toggle() {
    var showDate = action.value === 'date' || action.value === 'specific_date';
    if (field.id === 'donate_banner_date_field') {
      field.hidden = !showDate;
    }
    else {
      field.style.display = showDate ? '' : 'none';
    }
    date.required = showDate;
  }

  action.addEventListener('change', toggle);
  toggle();
})();
