/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This Source Code Form is "Incompatible With Secondary Licenses", as
 * defined by the Mozilla Public License, v. 2.0. */

document.addEventListener("DOMContentLoaded", () => {
  const password = document.getElementById("password");
  const password_confirm = document.getElementById("password_confirm");
  const on_change = (event) => {
    if (password.value == password_confirm.value) {
      console.log(password.value);
      console.log(password_confirm.value);
      password.setCustomValidity("");
      password_confirm.setCustomValidity("");
    } else {
      password.setCustomValidity("This password doesn't match");
      password_confirm.setCustomValidity("This password doesn't match");
    }
  };
  if (password && password_confirm) {
    password.addEventListener("change", on_change);
    password_confirm.addEventListener("change", on_change);
  }

  const cancel = document.getElementById("signup_cancel");
  if (cancel) {
    cancel.addEventListener("click", (event) => {
      const not_required = ['etiquette', 'password', 'password_confirm'];
      for (const id of not_required) {
        const field = document.getElementById(id);
        if (field) {
          field.required = false;
        }
      }
    });
  }
});
