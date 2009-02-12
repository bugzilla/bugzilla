/* The contents of this file are subject to the Mozilla Public
* License Version 1.1 (the "License"); you may not use this file
* except in compliance with the License. You may obtain a copy of
* the License at http://www.mozilla.org/MPL/
*
* Software distributed under the License is distributed on an "AS
* IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
* implied. See the License for the specific language governing
* rights and limitations under the License.
*
* The Original Code is the Bugzilla Bug Tracking System.
*
* Contributor(s): Guy Pyrzak <guy.pyrzak@gmail.com>
*                 
*/

var mini_login_constants;

function init_mini_login_form( suffix ) {
    var mini_login = document.getElementById('Bugzilla_login' +  suffix );
    var mini_password = document.getElementById('Bugzilla_password' +  suffix );
    // check if the login and password are blank and if they are
    //    put in the text login and password and make them slightly greyed out
    if( mini_login.value == "" && mini_password.value == "" ) {
        mini_login.value = mini_login_constants.login;
        mini_password.value = mini_login_constants.password;
        mini_password.type = "text";

        YAHOO.util.Dom.addClass(mini_login, "bz_mini_login_help");
        YAHOO.util.Dom.addClass(mini_password, "bz_mini_login_help");        
    }
}

function mini_login_on_focus( el ) {
    if( el.name == "Bugzilla_password" ){
        if( el.type != "password" ) {
            el.value = "";
            el.type = "password";
        }
    } else if ( el.value == mini_login_constants.login ) {
        if( el.value == mini_login_constants.login ) {
            el.value = "";
        }  
    }
    YAHOO.util.Dom.removeClass(el, "bz_mini_login_help");
}

function check_mini_login_fields( suffix ) {
    var mini_login = document.getElementById('Bugzilla_login' +  suffix );
    var mini_password = document.getElementById('Bugzilla_password' +  suffix );
    if(( mini_login.value != "" && mini_password.value != "" ) && 
       (  mini_login.value != mini_login_constants.login  && 
          mini_password.value != mini_login_constants.password )) {
      return true;
    }
    window.alert( mini_login_constants.warning );
    return false;
}
