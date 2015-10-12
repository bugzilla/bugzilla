// https://github.com/duosecurity/duo_perl
//
// Copyright (c) 2012, Duo Security, Inc.
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
//
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. The name of the author may not be used to endorse or promote products
//    derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
// IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
// NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
(function(a){var d,f,e=1,i,j=this,k,l=j.postMessage;a.postMessage=function(b,c,h){if(c){b=typeof b==="string"?b:a.param(b);h=h||parent;if(l)h.postMessage(b,c.replace(/([^:]+:\/\/[^\/]+).*/,"$1"));else if(c)h.location=c.replace(/#.*$/,"")+"#"+ +new Date+e++ +"&"+b}};a.receiveMessage=k=function(b,c,h){if(l){if(b){i&&k();i=function(g){if(typeof c==="string"&&g.origin!==c||a.isFunction(c)&&c(g.origin)===false)return false;b(g)}}if(j.addEventListener)j[b?"addEventListener":"removeEventListener"]("message",
i,false);else j[b?"attachEvent":"detachEvent"]("onmessage",i)}else{d&&clearInterval(d);d=null;if(b)d=setInterval(function(){var g=document.location.hash,m=/^#?\d+&/;if(g!==f&&m.test(g)){f=g;b({data:g.replace(m,"")})}},typeof c==="number"?c:typeof h==="number"?h:100)}}})(jQuery);
var D=jQuery,Duo={init:function(a){if(a)if(a.host){Duo._host=a.host;if(a.sig_request){Duo._sig_request=a.sig_request;if(Duo._sig_request.indexOf("ERR|")==0){a=Duo._sig_request.split("|");alert("Error: "+a[1])}else if(Duo._sig_request.indexOf(":")==-1)alert("Invalid sig_request value");else{var d=Duo._sig_request.split(":");if(d.length!=2)alert("Invalid sig_request value");else{Duo._duo_sig=d[0];Duo._app_sig=d[1];if(!a.post_action)a.post_action="";Duo._post_action=a.post_action;if(!a.post_argument)a.post_argument=
"sig_response";Duo._post_argument=a.post_argument}}}else alert("Error: missing 'sig_request' argument in Duo.init()")}else alert("Error: missing 'host' argument in Duo.init()");else alert("Error: missing arguments in Duo.init()")},ready:function(){var a=D("#duo_iframe");if(a.length){var d=D.param({tx:Duo._duo_sig,parent:document.location.href});a.attr("src","https://"+Duo._host+"/frame/web/v1/auth?"+d);D.receiveMessage(function(f){f=f.data+":"+Duo._app_sig;f=D('<input type="hidden">').attr("name",
Duo._post_argument).val(f);var e=D("#duo_form");if(!e.length){e=D("<form>");e.insertAfter(a)}e.attr("method","POST");e.attr("action",Duo._post_action);e.append(f);e.submit()},"https://"+Duo._host)}else alert("Error: missing IFRAME element with id 'duo_iframe'")}};D(document).ready(function(){Duo.ready()});
