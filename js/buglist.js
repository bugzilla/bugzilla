function SetCheckboxes(value) {
  let elements = document.querySelectorAll("input[type='checkbox'][name^='id_']");
  for (let item of elements) {
    item.checked = value;
  }
}

document.addEventListener("DOMContentLoaded", () => {
  let check_all = document.getElementById("check_all");
  let uncheck_all = document.getElementById("uncheck_all");
  if (check_all) {
    check_all.addEventListener("click", event => {
      SetCheckboxes(true);
      event.preventDefault();
    });
  }
  if (uncheck_all) {
    uncheck_all.addEventListener("click", event => {
      SetCheckboxes(false);
      event.preventDefault();
    });
  }
});
