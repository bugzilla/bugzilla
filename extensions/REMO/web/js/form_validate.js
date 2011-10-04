/**
 * Some Form Validation and Interaction
 **/
//Makes sure that there is an '@' in the address with a '.' 
//somewhere after it (and at least one character in between them

function isValidEmail(email) {
    var at_index = email.indexOf("@");
    var last_dot = email.lastIndexOf(".");
    return at_index > 0 && last_dot > (at_index + 1);
}

//Takes a DOM element id and makes sure that it is filled out
function isFilledOut(elem_id)  {
    var str = document.getElementById(elem_id).value;
    return str.length>0 && str!="noneselected";
}

function isChecked(elem_id) {
    return document.getElementById(elem_id).checked;
}
