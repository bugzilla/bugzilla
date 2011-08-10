var Dom = YAHOO.util.Dom;

function onSelectProduct() {
  var component = Dom.get('component');
  if (Dom.get('product').value == '') {
    bz_clearOptions(component);
    return;
  }
  selectProduct(Dom.get('product'), component);
  // selectProduct only supports __Any__ on both elements
  // we only want it on component, so add it back in
  try {
    component.add(new Option('__Any__', ''), component.options[0]);
  } catch(e) {
    // support IE
    component.add(new Option('__Any__', ''), 0);
  }
  component.value = '';
}

function onCommenterChange() {
  var commenter_is = Dom.get('commenter_is');
  if (Dom.get('commenter').value == 'is') {
    Dom.removeClass(commenter_is, 'hidden');
  } else {
    Dom.addClass(commenter_is, 'hidden');
  }
}

function onLastChange() {
  var last_is_span = Dom.get('last_is_span');
  if (Dom.get('last').value == 'is') {
    Dom.removeClass(last_is_span, 'hidden');
  } else {
    Dom.addClass(last_is_span, 'hidden');
  }
}

function onGenerateReport() {
  if (Dom.get('product').value == '') {
    alert('You must select a product.');
    return false;
  }
  if (Dom.get('component').value == '' && !Dom.get('component').options[0].selected) {
    alert('You must select at least one component.');
    return false;
  }
  if (!(Dom.get('filter_commenter').checked || Dom.get('filter_last').checked)) {
    alert('You must select at least one comment filter.');
    return false;
  }
  if (Dom.get('filter_commenter').checked
      && Dom.get('commenter').value == 'is'
      && Dom.get('commenter_is').value == '')
  {
    alert('You must specify the last commenter\'s email address.');
    return false;
  }
  if (Dom.get('filter_last').checked
      && Dom.get('last').value == 'is'
      && Dom.get('last_is').value == '')
  {
    alert('You must specify the "comment is older than" date.');
    return false;
  }
  return true;
}

YAHOO.util.Event.onDOMReady(function() {
  onSelectProduct();
  onCommenterChange();
  onLastChange();

  var component = Dom.get('component');
  if (selected_components.length == 0)
    return;
  component.options[0].selected = false;
  for (var i = 0, n = selected_components.length; i < n; i++) {
    var index = bz_optionIndex(component, selected_components[i]);
    if (index != -1)
      component.options[index].selected = true;
  }
});
