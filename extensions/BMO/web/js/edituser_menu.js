var admin_usermenu;

YAHOO.util.Event.onDOMReady(function() {
  admin_usermenu = new YAHOO.widget.Menu('admin_usermenu', { position : 'dynamic' });
  admin_usermenu.addItems([
    { text: 'Activity', url: '#', target: '_blank' },
    { text: 'Mail',     url: '#', target: '_blank' },
    { text: 'Edit',     url: '#', target: '_blank' }
  ]);
  admin_usermenu.render(document.body);
});

function show_admin_usermenu(event, id, email, show_edit) {
  if (!admin_usermenu)
    return;
  admin_usermenu.getItem(0).cfg.setProperty('url',
    'page.cgi?id=user_activity.html&action=run' +
    '&from=' + YAHOO.util.Date.format(new Date(new Date() - (1000 * 60 * 60 * 24 * 14)), {format: '%Y-%m-%d'}) +
    '&to=' + YAHOO.util.Date.format(new Date(), {format: '%Y-%m-%d'}) +
    '&who=' + encodeURIComponent(email));
  admin_usermenu.getItem(1).cfg.setProperty('url', 'mailto:' + encodeURIComponent(email));
  if (show_edit) {
    admin_usermenu.getItem(2).cfg.setProperty('url', 'editusers.cgi?action=edit&userid=' + id);
  } else {
    admin_usermenu.removeItem(2);
  }
  admin_usermenu.cfg.setProperty('xy', YAHOO.util.Event.getXY(event));
  admin_usermenu.show();
}

