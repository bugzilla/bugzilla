/*!
 * Javascript Cookie v1.5.1
 * https://github.com/js-cookie/js-cookie
 *
 * Copyright 2006, 2014 Klaus Hartl
 * Released under the MIT license
 */
(function(factory){var jQuery;if(typeof define==='function'&&define.amd){define(['jquery'],factory)}else if(typeof exports==='object'){try{jQuery=require('jquery')}catch(e){}
module.exports=factory(jQuery)}else{var _OldCookies=window.Cookies;var api=window.Cookies=factory(window.jQuery);api.noConflict=function(){window.Cookies=_OldCookies;return api}}}(function($){var pluses=/\+/g;function encode(s){return api.raw?s:encodeURIComponent(s)}
function decode(s){return api.raw?s:decodeURIComponent(s)}
function stringifyCookieValue(value){return encode(api.json?JSON.stringify(value):String(value))}
function parseCookieValue(s){if(s.indexOf('"')===0){s=s.slice(1,-1).replace(/\\"/g,'"').replace(/\\\\/g,'\\')}
try{s=decodeURIComponent(s.replace(pluses,' '));return api.json?JSON.parse(s):s}catch(e){}}
function read(s,converter){var value=api.raw?s:parseCookieValue(s);return isFunction(converter)?converter(value):value}
function extend(){var key,options;var i=0;var result={};for(;i<arguments.length;i++){options=arguments[i];for(key in options){result[key]=options[key]}}
return result}
function isFunction(obj){return Object.prototype.toString.call(obj)==='[object Function]'}
var api=function(key,value,options){if(arguments.length>1&&!isFunction(value)){options=extend(api.defaults,options);if(typeof options.expires==='number'){var days=options.expires,t=options.expires=new Date();t.setMilliseconds(t.getMilliseconds()+days*864e+5)}
return(document.cookie=[encode(key),'=',stringifyCookieValue(value),options.expires?'; expires='+options.expires.toUTCString():'',options.path?'; path='+options.path:'',options.domain?'; domain='+options.domain:'',options.secure?'; secure':''].join(''))}
var result=key?undefined:{},cookies=document.cookie?document.cookie.split('; '):[],i=0,l=cookies.length;for(;i<l;i++){var parts=cookies[i].split('='),name=decode(parts.shift()),cookie=parts.join('=');if(key===name){result=read(cookie,value);break}
if(!key&&(cookie=read(cookie))!==undefined){result[name]=cookie}}
return result};api.get=api.set=api;api.defaults={};api.remove=function(key,options){api(key,'',extend(options,{expires:-1}));return!api(key)};if($){$.cookie=api;$.removeCookie=api.remove}
return api}))