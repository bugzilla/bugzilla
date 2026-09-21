/* UserField extension.
 *
 * A minimal, dependency-free autocomplete for FREETEXT custom fields
 * that store a Bugzilla login name. Deliberately does NOT rely on
 * Bugzilla's own YUI-based YAHOO.bugzilla.userAutocomplete (js/field.js) -
 * some skins/installs don't load it on every page the same way stock
 * Bugzilla does, so this widget is fully self-sufficient: it calls
 * jsonrpc.cgi directly with plain fetch().
 *
 * IMPORTANT: this must POST, not GET. Bugzilla's JSON-RPC server
 * intentionally refuses cookie-based authentication on GET requests
 * (to prevent cross-site data leaks via JSONP), so a GET call would
 * always come back as an anonymous, permission-limited request. POST
 * with credentials included uses the browser's existing Bugzilla
 * session cookie, same as any other page on the site.
 */
(function () {
  'use strict';

  var MIN_QUERY_LENGTH = 3;
  var DEBOUNCE_MS = 300;

  function jsonRpcUserMatch(queryString, callback) {
    var body = JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method: 'User.get',
      params: [{match: [queryString], include_fields: ['name', 'real_name']}]
    });

    fetch('jsonrpc.cgi', {
      method: 'POST',
      credentials: 'same-origin',
      headers: {'Content-Type': 'application/json'},
      body: body
    })
      .then(function (resp) { return resp.json(); })
      .then(function (data) {
        if (!data || data.error) {
          callback([]);
          return;
        }
        callback((data.result && data.result.users) || []);
      })
      .catch(function () { callback([]); });
  }

  function buildDropdown() {
    var box = document.createElement('div');
    box.className = 'userfield-autocomplete-box';
    box.style.cssText =
      'position:absolute;z-index:1000;background:#fff;border:1px solid #ccc;' +
      'box-shadow:0 2px 6px rgba(0,0,0,.15);max-height:220px;overflow:auto;' +
      'font-size:12px;font-family:sans-serif;display:none;';
    document.body.appendChild(box);
    return box;
  }

  function positionDropdown(box, input) {
    var rect = input.getBoundingClientRect();
    box.style.left = (window.scrollX + rect.left) + 'px';
    box.style.top = (window.scrollY + rect.bottom) + 'px';
    box.style.minWidth = rect.width + 'px';
  }

  function initUserField(fieldId) {
    var input = document.getElementById(fieldId);
    if (!input || input.dataset.userfieldInit) return;
    input.dataset.userfieldInit = '1';
    input.setAttribute('autocomplete', 'off');

    var box = buildDropdown();
    var timer = null;

    function hide() {
      box.style.display = 'none';
      box.innerHTML = '';
    }

    function showResults(users) {
      box.innerHTML = '';
      if (!users.length) {
        hide();
        return;
      }
      users.forEach(function (u) {
        var item = document.createElement('div');
        item.textContent = u.real_name ? (u.real_name + ' <' + u.name + '>') : u.name;
        item.style.cssText = 'padding:4px 8px;cursor:pointer;';
        item.addEventListener('mouseenter', function () {
          item.style.background = '#e8f0fe';
        });
        item.addEventListener('mouseleave', function () {
          item.style.background = '';
        });
        // mousedown (not click) fires before the input's blur handler,
        // so we can grab the selection before the dropdown gets hidden.
        item.addEventListener('mousedown', function (ev) {
          ev.preventDefault();
          input.value = u.name;
          hide();
        });
        box.appendChild(item);
      });
      positionDropdown(box, input);
      box.style.display = 'block';
    }

    input.addEventListener('input', function () {
      var q = input.value.trim();
      clearTimeout(timer);
      if (q.length < MIN_QUERY_LENGTH) {
        hide();
        return;
      }
      timer = setTimeout(function () {
        jsonRpcUserMatch(q, showResults);
      }, DEBOUNCE_MS);
    });

    input.addEventListener('blur', function () {
      // Small delay so a mousedown-selection above still registers
      // before we wipe the dropdown out.
      setTimeout(hide, 150);
    });

    window.addEventListener('resize', function () { positionDropdown(box, input); });
    window.addEventListener('scroll', function () { positionDropdown(box, input); }, true);
  }

  window.UserFieldAutocomplete = {init: initUserField};
})();
