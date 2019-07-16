/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

/**
 * Reference or define the Bugzilla app namespace.
 * @namespace
 */
var Bugzilla = Bugzilla || {}; // eslint-disable-line no-var

Bugzilla.AdvancedSearch = {};

/**
 * Implement features in the Search By Change History section.
 */
Bugzilla.AdvancedSearch.HistoryFilter = class HistoryFilter {
  /**
   * Initialize a new HistoryFilter instance.
   */
  constructor() {
    this.$chfield = document.querySelector('#chfield');
    this.$chfieldfrom = document.querySelector('#chfieldfrom');
    this.$chfieldfrom_button = document.querySelector('#chfieldfrom + button');
    this.$chfieldto = document.querySelector('#chfieldto');
    this.$chfieldto_button = document.querySelector('#chfieldto + button');

    this.$chfieldfrom.addEventListener('input', event => this.on_date_change(event));
    this.$chfieldto.addEventListener('input', event => this.on_date_change(event));

    // Use on-event handler because `field.js` will update it
    this.$chfieldfrom_button.onclick = () => showCalendar('chfieldfrom');
    this.$chfieldto_button.onclick = () => showCalendar('chfieldto');

    createCalendar('chfieldfrom');
    createCalendar('chfieldto');
  }

  /**
   * Called whenever the date field value is updated.
   * @param {InputEvent} event `input` event fired on date fields.
   */
  on_date_change(event) {
    // Update the calendar when the user enters a date manually
    if (event.isTrusted) {
      updateCalendarFromField(event.target);
    }

    // Mark `<select>` required if the value is not empty
    this.$chfield.required = !!this.$chfieldfrom.value.trim() || !!this.$chfieldto.value.trim();
  }
};

/**
 * Implement Custom Search features.
 */
Bugzilla.CustomSearch = class CustomSearch {
  /**
   * Initialize a new CustomSearch instance.
   */
  constructor() {
    this.data = Bugzilla.CustomSearch.data = { group_count: 0, row_count: 0 };
    this.$container = document.querySelector('#custom-search');

    // Decode and store required data
    Object.entries(this.$container.dataset).forEach(([key, value]) => this.data[key] = JSON.parse(value));

    // Sort the fields by label instead of name
    {
      const { lang } = document.documentElement;
      const options = { sensitivity: 'base' };

      this.data.fields.sort((a, b) => a.label.localeCompare(b.label, lang, options));
    }

    this.restore();

    this.$container.addEventListener('change', () => this.save_state());
    this.$container.addEventListener('CustomSearch:ItemAdded', () => this.update_input_names());
    this.$container.addEventListener('CustomSearch:ItemRemoved', () => this.remove_empty_group());
    this.$container.addEventListener('CustomSearch:ItemMoved', () => this.remove_empty_group());
    this.$container.addEventListener('CustomSearch:DragStarted', event => this.enable_drop_targets(event));
    this.$container.addEventListener('CustomSearch:DragEnded', () => this.disable_drop_targets());
  }

  /**
   * Add rows and groups specified with the URL query or history state.
   */
  restore() {
    const { j_top, conditions } = history.state || this.data.initial;
    const groups = [];
    let level = 0;

    groups.push(new Bugzilla.CustomSearch.Group({ j: j_top, is_top: true, add_empty_row: !conditions.length }));
    groups[0].render(this.$container);

    // Use `let` to work around test failures on Firefox 47 (Bug 1101653)
    for (let condition of conditions) { // eslint-disable-line prefer-const
      // Skip empty conditions
      if (!condition || !condition.f) {
        continue;
      }

      // Stop if the condition is invalid (due to any extra CP)
      if (level < 0) {
        break;
      }

      const group = groups[level];

      if (condition.f === 'OP') {
        // OP = open parentheses = starting a new group
        groups[++level] = group.add_group(condition);
      } else if (condition.f === 'CP') {
        // OP = close parentheses = ending a new group
        level--;
      } else {
        group.add_row(condition);
      }
    }

    this.update_input_names();
  }

  /**
   * Update the `name` attribute on all the `<input>` elements when a row or group is added, removed or moved.
   */
  update_input_names() {
    let index = 1;
    let cp_index = 0;

    // Cache radio button states, which can be reset while renaming
    const radio_states =
      new Map([...this.$container.querySelectorAll('input[type="radio"]')].map(({ id, checked }) => [id, checked]));

    // Use spread syntax to work around test failures on Firefox 47. `NodeList.forEach` was added to Firefox 50
    [...this.$container.querySelectorAll('.group.top .condition')].forEach($item => {
      if ($item.matches('.group')) {
        // CP needs to be added after all the rows and nested subgroups within the current group.
        // Example: f1=OP, f2=product, f3=component, f4=OP, f5=reporter, f6=assignee, f7=CP, f8=CP
        cp_index = index + $item.querySelectorAll('.row').length + ($item.querySelectorAll('.group').length * 2) + 1;
      }

      [...$item.querySelectorAll('[name]')].filter($input => $input.closest('.condition') === $item).forEach($input => {
        $input.name = $input.value === 'CP' ? `f${cp_index}` : `${$input.name.charAt(0)}${index}`;
      });

      index++;

      if (index === cp_index) {
        index++;
      }
    });

    // Restore radio button states
    radio_states.forEach((checked, id) => document.getElementById(id).checked = checked);

    this.save_state();
  }

  /**
   * Save the current search conditions in the browser history, so these rows and groups can be restored after the user
   * reloads or navigates back to the page, just like native static form widgets.
   */
  save_state() {
    const form_data = new FormData(this.$container.closest('form'));
    const j_top = form_data.get('j_top');
    const conditions = [];

    for (let [name, value] of form_data.entries()) { // eslint-disable-line prefer-const
      const [, key, index] = name.match(/^([njfov])(\d+)$/) || [];

      if (key) {
        conditions[index] = Object.assign(conditions[index] || {}, { [key]: value });
      }
    }

    // The conditions will be the same format as an array of user-defined initial conditions embedded in the page.
    // Example: [{ f: 'OP', n: 1, j: 'AND' }, { f: 'product', o: 'equals', v: 'Bugzilla' }, { f: 'CP' }]
    history.replaceState(Object.assign(history.state || {}, { j_top, conditions }), document.title);
  }

  /**
   * Remove any empty group when a row or group is moved or removed.
   */
  remove_empty_group() {
    this.$container.querySelectorAll('.group').forEach($group => {
      if (!$group.querySelector('.condition') && !$group.matches('.top')) {
        $group.previousElementSibling.remove(); // drop target
        $group.remove();
      }
    });

    this.update_input_names();
  }

  /**
   * Enable drop targets between conditions when drag action is started.
   * @param {DragEvent} event `dragstart` event.
   */
  enable_drop_targets(event) {
    const $source = document.getElementById(event.detail.id);

    this.$container.querySelectorAll('.drop-target').forEach($target => {
      // The targets above/below the source or within the current group cannot be used for the `move` effect
      $target.setAttribute('aria-dropeffect', $target === $source.previousElementSibling ||
        $target === $source.nextElementSibling || $source.contains($target) ? 'copy' : 'copy move');
    });
  }

  /**
   * Disable drop targets between conditions when drag action is ended.
   */
  disable_drop_targets() {
    this.$container.querySelectorAll('[aria-dropeffect]').forEach($target => {
      $target.setAttribute('aria-dropeffect', 'none');
    });
  }
};

/**
 * Implement a Custom Search condition features shared by rows and groups.
 * @abstract
 */
Bugzilla.CustomSearch.Condition = class CustomSearchCondition {
  /**
   * Add a row or group to the given element.
   * @param {HTMLElement} $parent Parent node of the new element.
   * @param {HTMLElement} [$ref] Node before which the new element is inserted.
   */
  render($parent, $ref = null) {
    const { id, type, condition } = this;

    $parent.insertBefore(this.$element, $ref);

    this.$element.dispatchEvent(new CustomEvent('CustomSearch:ItemAdded', {
      bubbles: true,
      detail: { id, type, condition },
    }));
  }

  /**
   * Remove a row or group from view.
   */
  remove() {
    const { id, type, condition } = this;
    const $parent = this.$element.parentElement;

    this.$element.remove();

    $parent.dispatchEvent(new CustomEvent('CustomSearch:ItemRemoved', {
      bubbles: true,
      detail: { id, type, condition },
    }));
  }

  /**
   * Enable drag action of a row or group.
   */
  enable_drag() {
    this.$element.draggable = true;
    this.$element.setAttribute('aria-grabbed', 'true');
    this.$action_grab.setAttribute('aria-pressed', 'true');
  }

  /**
   * Disable drag action of a row or group.
   */
  disable_drag() {
    this.$element.draggable = false;
    this.$element.setAttribute('aria-grabbed', 'false');
    this.$action_grab.setAttribute('aria-pressed', 'false');
  }

  /**
   * Handle drag events at the source, which is a row or group.
   * @param {DragEvent} event One of drag-related events.
   */
  handle_drag(event) {
    event.stopPropagation();

    const { id } = this;

    if (event.type === 'dragstart') {
      event.dataTransfer.setData('application/x-cs-condition', id);
      event.dataTransfer.effectAllowed = 'copyMove';

      this.$element.dispatchEvent(new CustomEvent('CustomSearch:DragStarted', { bubbles: true, detail: { id } }));
    }

    if (event.type === 'dragend') {
      this.disable_drag();
      this.$element.dispatchEvent(new CustomEvent('CustomSearch:DragEnded', { bubbles: true, detail: { id } }));
    }
  }
};

/**
 * Implement a Custom Search group.
 */
Bugzilla.CustomSearch.Group = class CustomSearchGroup extends Bugzilla.CustomSearch.Condition {
  /**
   * Initialize a new CustomSearchGroup instance.
   * @param {Object} [condition] Search condition.
   * @param {Boolean} [condition.n] Whether to use NOT.
   * @param {String} [condition.j] How to join: AND, AND_G or OR.
   * @param {Boolean} [condition.is_top] Whether this is the topmost group within the custom search container.
   * @param {Boolean} [condition.add_empty_row] Whether to add an empty new row to the condition area by default.
   */
  constructor(condition = {}) {
    super();

    this.type = 'group';
    this.condition = condition;

    const $placeholder = document.createElement('div');
    const { n = false, j = 'AND', is_top = false, add_empty_row = false } = condition;
    const { data } = Bugzilla.CustomSearch;
    const { strings: str } = data;
    const count = ++data.group_count;
    const index = data.group_count + data.row_count;
    const id = this.id = `group-${count}`;

    $placeholder.innerHTML = `
      <section role="group" id="${id}" class="condition group ${is_top ? 'top' : ''}" draggable="false"
          aria-grabbed="false" aria-label="${str.group_name.replace('{ $count }', count)}">
        ${is_top ? '' : `<input type="hidden" name="f${index}" value="OP">`}
        <header role="toolbar">
          ${is_top ? '' : `
            <button type="button" class="iconic" aria-label="${str.grab}" data-action="grab">
              <span class="icon" aria-hidden="true"></span>
            </button>
            <label><input type="checkbox" name="n${index}" value="1" ${n ? 'checked' : ''}> ${str.not}</label>
          `}
          <div class="match">
            <div role="radiogroup" class="buttons toggle join" aria-label="${str.join_options}">
              <div class="item">
                <input id="${id}-j-r1" class="join" type="radio" name="${is_top ? 'j_top' : `j${index}`}" value="AND"
                  ${j === 'AND' ? 'checked' : ''} aria-label="${str.match_all}">
                <label for="${id}-j-r1" title="${str.match_all_hint}">${str.match_all}</label>
              </div>
              <div class="item">
                <input id="${id}-j-r2" class="join" type="radio" name="${is_top ? 'j_top' : `j${index}`}" value="AND_G"
                  ${j === 'AND_G' ? 'checked' : ''} aria-label="${str.match_all_g}">
                <label for="${id}-j-r2" title="${str.match_all_g_hint}">${str.match_all_g}</label>
              </div>
              <div class="item">
                <input id="${id}-j-r3" class="join" type="radio" name="${is_top ? 'j_top' : `j${index}`}" value="OR"
                  ${j === 'OR' ? 'checked' : ''} aria-label="${str.match_any}">
                <label for="${id}-j-r3" title="${str.match_any_hint}">${str.match_any}</label>
              </div>
            </div>
          </div>
          ${is_top ? '' : `
            <button type="button" class="iconic" aria-label="${str.remove}" data-action="remove">
              <span class="icon" aria-hidden="true"></span>
            </button>
          `}
        </header>
        <div class="conditions"></div>
        <footer role="toolbar">
          <button type="button" class="minor iconic-text" data-action="add-row" aria-label="${str.add_row}">
            <span class="icon" aria-hidden="true"></span> ${str.row}
          </button>
          <button type="button" class="minor iconic-text" data-action="add-group" aria-label="${str.add_group}">
            <span class="icon" aria-hidden="true"></span> ${str.group}
          </button>
        </footer>
        ${is_top ? '' : `<input type="hidden" name="f${index}" value="CP">`}
      </section>
    `;

    this.$element = $placeholder.firstElementChild;
    this.$join = this.$element.querySelector('.buttons.join');
    this.$join_and = this.$join.querySelector('[value="AND"]');
    this.$join_and_g = this.$join.querySelector('[value="AND_G"]');
    this.$conditions = this.$element.querySelector('.conditions');
    this.$action_grab = this.$element.querySelector('[data-action="grab"]');
    this.$action_remove = this.$element.querySelector('[data-action="remove"]');
    this.$action_add_group = this.$element.querySelector('[data-action="add-group"]');
    this.$action_add_row = this.$element.querySelector('[data-action="add-row"]');

    this.$element.addEventListener('change', event => this.check_joined_fields(event));
    this.$element.addEventListener('dragstart', event => this.handle_drag(event));
    this.$element.addEventListener('dragend', event => this.handle_drag(event));
    this.$element.addEventListener('CustomSearch:ItemAdded', () => this.update_join_option());
    this.$element.addEventListener('CustomSearch:ItemRemoved', () => this.update_join_option());
    this.$element.addEventListener('CustomSearch:ItemMoved', () => this.update_join_option());
    this.$element.addEventListener('CustomSearch:ItemDuplicating', event => this.duplicate_items(event));
    this.$action_add_group.addEventListener('click', () => this.add_group({ add_empty_row: true }));
    this.$action_add_row.addEventListener('click', () => this.add_row());

    if (!is_top) {
      this.$action_grab.addEventListener('mousedown', () => this.enable_drag());
      this.$action_grab.addEventListener('mouseup', () => this.disable_drag());
      this.$action_remove.addEventListener('click', () => this.remove());
    }

    this.add_drop_target();

    if (add_empty_row) {
      this.add_row();
    }
  }

  /**
   * Get an array of elements within the condition area but not in the subgroups.
   * @param {String} selector CSS selector to find elements.
   * @returns {Array.<HTMLElement>} Elements that match the given selector.
   */
  get_elements(selector) {
    return [...this.$element.querySelectorAll(selector)]
      .filter($element => $element.closest('.group') === this.$element);
  }

  /**
   * Update `<select class="field">` when the join option is changed, or the value on `<select class="field">` is
   * changed while the "Match Any (Same Field)" join option is enabled.
   * @param {Event} event `change` event.
   */
  check_joined_fields(event) {
    const $target = event.target;
    const fields = this.get_elements('.conditions select.field');
    let field_name;

    if ($target.matches('input.join') && this.get_elements('input.join').includes($target)) {
      this.condition.j = $target.value;

      if (fields.length) {
        field_name = fields[0].value;
      }
    }

    if (this.condition.j === 'AND_G') {
      if ($target.matches('select.field') && fields.includes($target)) {
        field_name = $target.value;
      }

      if (field_name) {
        // Copy the field name on the first or updated row to other rows
        fields.forEach($select => $select.value = field_name);
      }
    }
  }

  /**
   * Update the join option when a subgroup is added or removed. If there's any subgroup, the "Match Any (Same Field)"
   * option must be disabled.
   */
  update_join_option() {
    const has_group = !!this.$conditions.querySelector('.group');

    if (has_group && this.$join_and_g.checked) {
      this.$join_and.checked = true;
      this.condition.j = 'AND';
    }

    this.$join_and_g.disabled = has_group;
  }

  /**
   * Add a new subgroup to the condition area.
   * @param {Object} [condition] Search condition.
   * @param {HTMLElement} [$ref] Node before which the new element is inserted.
   * @returns {CustomSearchGroup} New group object.
   */
  add_group(condition = {}, $ref = null) {
    const group = new Bugzilla.CustomSearch.Group(condition);

    group.render(this.$conditions, $ref);
    this.add_drop_target(group.$element.nextElementSibling);

    return group;
  }

  /**
   * Add a new child row to the condition area.
   * @param {Object} [condition] Search condition.
   * @param {HTMLElement} [$ref] Node before which the new element is inserted.
   * @returns {CustomSearchRow} New row object.
   */
  add_row(condition = {}, $ref = null) {
    // Copy the field name from the group's last row when a new row is added manually or the group's join option is
    // "Match Any (Same Field)"
    if (!condition.f || this.condition.j === 'AND_G') {
      const last_field = this.get_elements('.conditions select.field').pop();

      if (last_field) {
        condition.f = last_field.value;
      }
    }

    const row = new Bugzilla.CustomSearch.Row(condition);

    row.render(this.$conditions, $ref);
    this.add_drop_target(row.$element.nextElementSibling);

    return row;
  }

  /**
   * Add a new drop target to the condition area.
   * @param {HTMLElement} [$ref] Node before which the new element is inserted.
   */
  add_drop_target($ref = null) {
    this.$conditions.insertBefore((new Bugzilla.CustomSearch.DropTarget()).$element, $ref);
  }

  /**
   * Duplicate one or more drag & dropped items.
   * @param {CustomEvent} event `CustomSearch:ItemDuplicating` event.
   * @see CustomSearch.restore
   */
  duplicate_items(event) {
    const { conditions, $target } = event.detail;
    const groups = [this];
    let level = 0;

    for (let condition of conditions) { // eslint-disable-line prefer-const
      const group = groups[level];
      const $ref = level === 0 ? $target.nextElementSibling : null;

      // Skip empty conditions
      if (!condition || !condition.f) {
        continue;
      }

      if (condition.f === 'OP') {
        // OP = open parentheses = starting a new group
        groups[++level] = group.add_group(condition, $ref);
      } else if (condition.f === 'CP') {
        // OP = close parentheses = ending a new group
        level--;
      } else {
        group.add_row(condition, $ref);
      }
    }
  }
};

/**
 * Implement a Custom Search row.
 */
Bugzilla.CustomSearch.Row = class CustomSearchRow extends Bugzilla.CustomSearch.Condition {
  /**
   * Initialize a new CustomSearchRow instance.
   * @param {Object} [condition] Search condition.
   * @param {Boolean} [condition.n] Whether to use NOT.
   * @param {String} [condition.f] Field name to be selected in the dropdown list.
   * @param {String} [condition.o] Operator name to be selected in the dropdown list.
   * @param {String} [condition.v] Field value.
   */
  constructor(condition = {}) {
    super();

    this.type = 'row';
    this.condition = condition;

    const { n = false, f = 'noop', o = 'noop', v = '' } = condition;
    const $placeholder = document.createElement('div');
    const { data } = Bugzilla.CustomSearch;
    const { strings: str, fields, types } = data;
    const count = ++data.row_count;
    const index = data.group_count + data.row_count;
    const id = this.id = `row-${count}`;

    $placeholder.innerHTML = `
      <div role="group" id="${id}" class="condition row" draggable="false" aria-grabbed="false"
          aria-label="${str.row_name.replace('{ $count }', count)}">
        <button type="button" class="iconic" aria-label="${str.grab}" aria-pressed="false" data-action="grab">
          <span class="icon" aria-hidden="true"></span>
        </button>
        <label><input type="checkbox" name="n${index}" value="1" ${n ? 'checked' : ''}> ${str.not}</label>
        <select class="field" name="f${index}" aria-label="${str.field}">
          ${fields.map(({ value, label }) => `
            <option value="${value.htmlEncode()}" ${f === value ? 'selected' : ''}>${label.htmlEncode()}</option>
          `).join('')}
        </select>
        <select class="operator" name="o${index}" aria-label="${str.operator}">
          ${types.map(({ value, label }) => `
            <option value="${value.htmlEncode()}" ${o === value ? 'selected' : ''}>${label.htmlEncode()}</option>
          `).join('')}
        </select>
        <input class="value" type="text" name="v${index}" value="${v.htmlEncode()}" aria-label="${str.value}">
        <button type="button" class="iconic" aria-label="${str.remove}" data-action="remove">
          <span class="icon" aria-hidden="true"></span>
        </button>
      </div>
    `;

    this.$element = $placeholder.firstElementChild;
    this.$action_grab = this.$element.querySelector('[data-action="grab"]');
    this.$action_remove = this.$element.querySelector('[data-action="remove"]');
    this.$select_field = this.$element.querySelector('select.field');
    this.$select_operator = this.$element.querySelector('select.operator');
    this.$input_value = this.$element.querySelector('input.value');

    this.$element.addEventListener('dragstart', event => this.handle_drag(event));
    this.$element.addEventListener('dragend', event => this.handle_drag(event));
    this.$action_grab.addEventListener('mousedown', () => this.enable_drag());
    this.$action_grab.addEventListener('mouseup', () => this.disable_drag());
    this.$action_remove.addEventListener('click', () => this.remove());
    this.$select_field.addEventListener('change', () => this.field_onchange());
  }

  /**
   * Called whenever a field option is selected.
   */
  field_onchange() {
    const is_anything = this.$select_field.value === 'anything';

    // Add support for the "anything" special field that allows to search the bug history. When it's selected, disable
    // search types other than "changed before", "changed after", "changed from", "changed to", "changed by", and make
    // "changed by" selected for convenience.
    for (const $option of this.$select_operator.options) {
      $option.disabled = is_anything ? !$option.value.match(/changed\w+/) : false;
      $option.selected = $option.value === (is_anything ? 'changedby' : 'noop');
    }
  }
};

/**
 * Implement a Custom Search drop target.
 */
Bugzilla.CustomSearch.DropTarget = class CustomSearchDropTarget {
  /**
   * Initialize a new CustomSearchDropTarget instance.
   */
  constructor() {
    const $placeholder = document.createElement('div');

    $placeholder.innerHTML = `
      <div role="separator" class="drop-target" aria-dropeffect="none">
        <div class="indicator"></div>
      </div>
    `;

    this.$element = $placeholder.firstElementChild;

    this.$element.addEventListener('dragenter', event => this.handle_drag(event));
    this.$element.addEventListener('dragover', event => this.handle_drag(event));
    this.$element.addEventListener('dragleave', event => this.handle_drag(event));
    this.$element.addEventListener('drop', event => this.handle_drag(event));
  }

  /**
   * Handle drag events at the target.
   * @param {DragEvent} event One of drag-related events.
   */
  handle_drag(event) {
    const { type, dataTransfer: dt } = event;
    const effect_allowed = this.$element.getAttribute('aria-dropeffect').split(' ');

    // Chrome and Safari don't set `dropEffect` while Firefox does
    if (dt.dropEffect === 'none') {
      if (dt.effectAllowed === 'copy' && effect_allowed.includes('copy')) {
        dt.dropEffect = 'copy';
      } else if (dt.effectAllowed === 'copyMove' && effect_allowed.includes('move')) {
        dt.dropEffect = 'move';
      }
    } else {
      // The `move` effect is not allowed in some cases
      if (!effect_allowed.includes(dt.dropEffect)) {
        dt.dropEffect = 'none';
      }
    }

    if (type === 'dragenter' && dt.dropEffect !== 'none') {
      this.$element.classList.add('dragover');
    }

    if (type === 'dragover') {
      event.preventDefault();
    }

    if (type === 'dragleave') {
      this.$element.classList.remove('dragover');
    }

    if (type === 'drop') {
      event.preventDefault();

      const source_id = dt.getData('application/x-cs-condition');
      const $source = document.getElementById(source_id);

      this.$element.classList.remove('dragover');

      if (dt.dropEffect === 'copy') {
        const conditions = [];

        // Create an array in the same format as the initial conditions and history-saved state
        $source.querySelectorAll('[name]').forEach($input => {
          if (($input.type === 'radio' || $input.type === 'checkbox') && !$input.checked) {
            return;
          }

          const [, key, index] = $input.name.match(/^([njfov])(\d+)$/) || [];

          conditions[index] = Object.assign(conditions[index] || {}, { [key]: $input.value });
        });

        // Let the parent group to duplicate the rows and groups
        this.$element.closest('.group').dispatchEvent(new CustomEvent('CustomSearch:ItemDuplicating', {
          detail: { conditions, $target: this.$element },
        }));
      }

      if (dt.dropEffect === 'move') {
        this.$element.insertAdjacentElement('beforebegin', $source.previousElementSibling); // drop target
        this.$element.insertAdjacentElement('beforebegin', $source);

        $source.parentElement.dispatchEvent(new CustomEvent('CustomSearch:ItemMoved', {
          bubbles: true,
          detail: { id: source_id, type: $source.matches('.group') ? 'group' : 'row' },
        }));
      }
    }
  }
};

window.addEventListener('DOMContentLoaded', () => {
  new Bugzilla.AdvancedSearch.HistoryFilter();
  new Bugzilla.CustomSearch();
}, { once: true });
