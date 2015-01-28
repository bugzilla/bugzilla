(function($,undefined){$.support.htmlMenuitem=('HTMLMenuItemElement'in window);$.support.htmlCommand=('HTMLCommandElement'in window);$.support.eventSelectstart=("onselectstart"in document.documentElement);if(!$.ui||!$.ui.widget){var _cleanData=$.cleanData;$.cleanData=function(elems){for(var i=0,elem;(elem=elems[i])!=null;i++){try{$(elem).triggerHandler("remove");}catch(e){}}
_cleanData(elems);};}
var
$currentTrigger=null,initialized=false,$win=$(window),counter=0,namespaces={},menus={},types={},defaults={selector:null,appendTo:null,trigger:"right",autoHide:false,delay:200,reposition:true,determinePosition:function($menu){if($.ui&&$.ui.position){$menu.css('display','block').position({my:"center top",at:"center bottom",of:this,offset:"0 5",collision:"fit"}).css('display','none');}else{var offset=this.offset();offset.top+=this.outerHeight();offset.left+=this.outerWidth()/2-$menu.outerWidth()/2;$menu.css(offset);}},position:function(opt,x,y){var $this=this,offset;if(!x&&!y){opt.determinePosition.call(this,opt.$menu);return;}else if(x==="maintain"&&y==="maintain"){offset=opt.$menu.position();}else{offset={top:y,left:x};}
var bottom=$win.scrollTop()+$win.height(),right=$win.scrollLeft()+$win.width(),height=opt.$menu.height(),width=opt.$menu.width();if(offset.top+height>bottom){offset.top-=height;}
if(offset.left+width>right){offset.left-=width;}
opt.$menu.css(offset);},positionSubmenu:function($menu){if($.ui&&$.ui.position){$menu.css('display','block').position({my:"left top",at:"right top",of:this,collision:"flipfit fit"}).css('display','');}else{var offset={top:0,left:this.outerWidth()};$menu.css(offset);}},zIndex:1,animation:{duration:50,show:'slideDown',hide:'slideUp'},events:{show:$.noop,hide:$.noop},callback:null,items:{}},hoveract={timer:null,pageX:null,pageY:null},zindex=function($t){var zin=0,$tt=$t;while(true){zin=Math.max(zin,parseInt($tt.css('z-index'),10)||0);$tt=$tt.parent();if(!$tt||!$tt.length||"html body".indexOf($tt.prop('nodeName').toLowerCase())>-1){break;}}
return zin;},handle={abortevent:function(e){e.preventDefault();e.stopImmediatePropagation();},contextmenu:function(e){var $this=$(this);e.preventDefault();e.stopImmediatePropagation();if(e.data.trigger!='right'&&e.originalEvent){return;}
if($this.hasClass('context-menu-active')){return;}
if(!$this.hasClass('context-menu-disabled')){$currentTrigger=$this;if(e.data.build){var built=e.data.build($currentTrigger,e);if(built===false){return;}
e.data=$.extend(true,{},defaults,e.data,built||{});if(!e.data.items||$.isEmptyObject(e.data.items)){if(window.console){(console.error||console.log)("No items specified to show in contextMenu");}
throw new Error('No Items specified');}
e.data.$trigger=$currentTrigger;op.create(e.data);}
op.show.call($this,e.data,e.pageX,e.pageY);}},click:function(e){e.preventDefault();e.stopImmediatePropagation();$(this).trigger($.Event("contextmenu",{data:e.data,pageX:e.pageX,pageY:e.pageY}));},mousedown:function(e){var $this=$(this);if($currentTrigger&&$currentTrigger.length&&!$currentTrigger.is($this)){$currentTrigger.data('contextMenu').$menu.trigger('contextmenu:hide');}
if(e.button==2){$currentTrigger=$this.data('contextMenuActive',true);}},mouseup:function(e){var $this=$(this);if($this.data('contextMenuActive')&&$currentTrigger&&$currentTrigger.length&&$currentTrigger.is($this)&&!$this.hasClass('context-menu-disabled')){e.preventDefault();e.stopImmediatePropagation();$currentTrigger=$this;$this.trigger($.Event("contextmenu",{data:e.data,pageX:e.pageX,pageY:e.pageY}));}
$this.removeData('contextMenuActive');},mouseenter:function(e){var $this=$(this),$related=$(e.relatedTarget),$document=$(document);if($related.is('.context-menu-list')||$related.closest('.context-menu-list').length){return;}
if($currentTrigger&&$currentTrigger.length){return;}
hoveract.pageX=e.pageX;hoveract.pageY=e.pageY;hoveract.data=e.data;$document.on('mousemove.contextMenuShow',handle.mousemove);hoveract.timer=setTimeout(function(){hoveract.timer=null;$document.off('mousemove.contextMenuShow');$currentTrigger=$this;$this.trigger($.Event("contextmenu",{data:hoveract.data,pageX:hoveract.pageX,pageY:hoveract.pageY}));},e.data.delay);},mousemove:function(e){hoveract.pageX=e.pageX;hoveract.pageY=e.pageY;},mouseleave:function(e){var $related=$(e.relatedTarget);if($related.is('.context-menu-list')||$related.closest('.context-menu-list').length){return;}
try{clearTimeout(hoveract.timer);}catch(e){}
hoveract.timer=null;},layerClick:function(e){var $this=$(this),root=$this.data('contextMenuRoot'),mouseup=false,button=e.button,x=e.pageX,y=e.pageY,target,offset,selectors;e.preventDefault();e.stopImmediatePropagation();setTimeout(function(){var $window,hideshow,possibleTarget;var triggerAction=((root.trigger=='left'&&button===0)||(root.trigger=='right'&&button===2));if(document.elementFromPoint){root.$layer.hide();target=document.elementFromPoint(x-$win.scrollLeft(),y-$win.scrollTop());root.$layer.show();}
if(root.reposition&&triggerAction){if(document.elementFromPoint){if(root.$trigger.is(target)||root.$trigger.has(target).length){root.position.call(root.$trigger,root,x,y);return;}}else{offset=root.$trigger.offset();$window=$(window);offset.top+=$window.scrollTop();if(offset.top<=e.pageY){offset.left+=$window.scrollLeft();if(offset.left<=e.pageX){offset.bottom=offset.top+root.$trigger.outerHeight();if(offset.bottom>=e.pageY){offset.right=offset.left+root.$trigger.outerWidth();if(offset.right>=e.pageX){root.position.call(root.$trigger,root,x,y);return;}}}}}}
if(target&&triggerAction){root.$trigger.one('contextmenu:hidden',function(){$(target).contextMenu({x:x,y:y});});}
root.$menu.trigger('contextmenu:hide');},50);},keyStop:function(e,opt){if(!opt.isInput){e.preventDefault();}
e.stopPropagation();},key:function(e){var opt=$currentTrigger.data('contextMenu')||{};switch(e.keyCode){case 9:case 38:handle.keyStop(e,opt);if(opt.isInput){if(e.keyCode==9&&e.shiftKey){e.preventDefault();opt.$selected&&opt.$selected.find('input, textarea, select').blur();opt.$menu.trigger('prevcommand');return;}else if(e.keyCode==38&&opt.$selected.find('input, textarea, select').prop('type')=='checkbox'){e.preventDefault();return;}}else if(e.keyCode!=9||e.shiftKey){opt.$menu.trigger('prevcommand');return;}
case 40:handle.keyStop(e,opt);if(opt.isInput){if(e.keyCode==9){e.preventDefault();opt.$selected&&opt.$selected.find('input, textarea, select').blur();opt.$menu.trigger('nextcommand');return;}else if(e.keyCode==40&&opt.$selected.find('input, textarea, select').prop('type')=='checkbox'){e.preventDefault();return;}}else{opt.$menu.trigger('nextcommand');return;}
break;case 37:handle.keyStop(e,opt);if(opt.isInput||!opt.$selected||!opt.$selected.length){break;}
if(!opt.$selected.parent().hasClass('context-menu-root')){var $parent=opt.$selected.parent().parent();opt.$selected.trigger('contextmenu:blur');opt.$selected=$parent;return;}
break;case 39:handle.keyStop(e,opt);if(opt.isInput||!opt.$selected||!opt.$selected.length){break;}
var itemdata=opt.$selected.data('contextMenu')||{};if(itemdata.$menu&&opt.$selected.hasClass('context-menu-submenu')){opt.$selected=null;itemdata.$selected=null;itemdata.$menu.trigger('nextcommand');return;}
break;case 35:case 36:if(opt.$selected&&opt.$selected.find('input, textarea, select').length){return;}else{(opt.$selected&&opt.$selected.parent()||opt.$menu)
.children(':not(.disabled, .not-selectable)')[e.keyCode==36?'first':'last']()
.trigger('contextmenu:focus');e.preventDefault();return;}
break;case 13:handle.keyStop(e,opt);if(opt.isInput){if(opt.$selected&&!opt.$selected.is('textarea, select')){e.preventDefault();return;}
break;}
opt.$selected&&opt.$selected.trigger('mouseup');return;case 32:case 33:case 34:handle.keyStop(e,opt);return;case 27:handle.keyStop(e,opt);opt.$menu.trigger('contextmenu:hide');return;default:var k=(String.fromCharCode(e.keyCode)).toUpperCase();if(opt.accesskeys[k]){opt.accesskeys[k].$node.trigger(opt.accesskeys[k].$menu?'contextmenu:focus':'mouseup');return;}
break;}
e.stopPropagation();opt.$selected&&opt.$selected.trigger(e);},prevItem:function(e){e.stopPropagation();var opt=$(this).data('contextMenu')||{};if(opt.$selected){var $s=opt.$selected;opt=opt.$selected.parent().data('contextMenu')||{};opt.$selected=$s;}
var $children=opt.$menu.children(),$prev=!opt.$selected||!opt.$selected.prev().length?$children.last():opt.$selected.prev(),$round=$prev;while($prev.hasClass('disabled')||$prev.hasClass('not-selectable')){if($prev.prev().length){$prev=$prev.prev();}else{$prev=$children.last();}
if($prev.is($round)){return;}}
if(opt.$selected){handle.itemMouseleave.call(opt.$selected.get(0),e);}
handle.itemMouseenter.call($prev.get(0),e);var $input=$prev.find('input, textarea, select');if($input.length){$input.focus();}},nextItem:function(e){e.stopPropagation();var opt=$(this).data('contextMenu')||{};if(opt.$selected){var $s=opt.$selected;opt=opt.$selected.parent().data('contextMenu')||{};opt.$selected=$s;}
var $children=opt.$menu.children(),$next=!opt.$selected||!opt.$selected.next().length?$children.first():opt.$selected.next(),$round=$next;while($next.hasClass('disabled')||$next.hasClass('not-selectable')){if($next.next().length){$next=$next.next();}else{$next=$children.first();}
if($next.is($round)){return;}}
if(opt.$selected){handle.itemMouseleave.call(opt.$selected.get(0),e);}
handle.itemMouseenter.call($next.get(0),e);var $input=$next.find('input, textarea, select');if($input.length){$input.focus();}},focusInput:function(e){var $this=$(this).closest('.context-menu-item'),data=$this.data(),opt=data.contextMenu,root=data.contextMenuRoot;root.$selected=opt.$selected=$this;root.isInput=opt.isInput=true;},blurInput:function(e){var $this=$(this).closest('.context-menu-item'),data=$this.data(),opt=data.contextMenu,root=data.contextMenuRoot;root.isInput=opt.isInput=false;},menuMouseenter:function(e){var root=$(this).data().contextMenuRoot;root.hovering=true;},menuMouseleave:function(e){var root=$(this).data().contextMenuRoot;if(root.$layer&&root.$layer.is(e.relatedTarget)){root.hovering=false;}},itemMouseenter:function(e){var $this=$(this),data=$this.data(),opt=data.contextMenu,root=data.contextMenuRoot;root.hovering=true;if(e&&root.$layer&&root.$layer.is(e.relatedTarget)){e.preventDefault();e.stopImmediatePropagation();}
(opt.$menu?opt:root).$menu
.children('.hover').trigger('contextmenu:blur');if($this.hasClass('disabled')||$this.hasClass('not-selectable')){opt.$selected=null;return;}
$this.trigger('contextmenu:focus');},itemMouseleave:function(e){var $this=$(this),data=$this.data(),opt=data.contextMenu,root=data.contextMenuRoot;if(root!==opt&&root.$layer&&root.$layer.is(e.relatedTarget)){root.$selected&&root.$selected.trigger('contextmenu:blur');e.preventDefault();e.stopImmediatePropagation();root.$selected=opt.$selected=opt.$node;return;}
$this.trigger('contextmenu:blur');},itemClick:function(e){var $this=$(this),data=$this.data(),opt=data.contextMenu,root=data.contextMenuRoot,key=data.contextMenuKey,callback;if(!opt.items[key]||$this.is('.disabled, .context-menu-submenu, .context-menu-separator, .not-selectable')){return;}
e.preventDefault();e.stopImmediatePropagation();if($.isFunction(root.callbacks[key])&&Object.prototype.hasOwnProperty.call(root.callbacks,key)){callback=root.callbacks[key];}else if($.isFunction(root.callback)){callback=root.callback;}else{return;}
if(callback.call(root.$trigger,key,root)!==false){root.$menu.trigger('contextmenu:hide');}else if(root.$menu.parent().length){op.update.call(root.$trigger,root);}},inputClick:function(e){e.stopImmediatePropagation();},hideMenu:function(e,data){var root=$(this).data('contextMenuRoot');op.hide.call(root.$trigger,root,data&&data.force);},focusItem:function(e){e.stopPropagation();var $this=$(this),data=$this.data(),opt=data.contextMenu,root=data.contextMenuRoot;$this.addClass('hover')
.siblings('.hover').trigger('contextmenu:blur');opt.$selected=root.$selected=$this;if(opt.$node){root.positionSubmenu.call(opt.$node,opt.$menu);}},blurItem:function(e){e.stopPropagation();var $this=$(this),data=$this.data(),opt=data.contextMenu,root=data.contextMenuRoot;$this.removeClass('hover');opt.$selected=null;}},op={show:function(opt,x,y){var $trigger=$(this),offset,css={};$('#context-menu-layer').trigger('mousedown');opt.$trigger=$trigger;if(opt.events.show.call($trigger,opt)===false){$currentTrigger=null;return;}
op.update.call($trigger,opt);opt.position.call($trigger,opt,x,y);if(opt.zIndex){css.zIndex=zindex($trigger)+opt.zIndex;}
op.layer.call(opt.$menu,opt,css.zIndex);opt.$menu.find('ul').css('zIndex',css.zIndex+1);opt.$menu.css(css)[opt.animation.show](opt.animation.duration,function(){$trigger.trigger('contextmenu:visible');});$trigger
.data('contextMenu',opt)
.addClass("context-menu-active");$(document).off('keydown.contextMenu').on('keydown.contextMenu',handle.key);if(opt.autoHide){$(document).on('mousemove.contextMenuAutoHide',function(e){var pos=$trigger.offset();pos.right=pos.left+$trigger.outerWidth();pos.bottom=pos.top+$trigger.outerHeight();if(opt.$layer&&!opt.hovering&&(!(e.pageX>=pos.left&&e.pageX<=pos.right)||!(e.pageY>=pos.top&&e.pageY<=pos.bottom))){opt.$menu.trigger('contextmenu:hide');}});}},hide:function(opt,force){var $trigger=$(this);if(!opt){opt=$trigger.data('contextMenu')||{};}
if(!force&&opt.events&&opt.events.hide.call($trigger,opt)===false){return;}
$trigger
.removeData('contextMenu')
.removeClass("context-menu-active");if(opt.$layer){setTimeout((function($layer){return function(){$layer.remove();};})(opt.$layer),10);try{delete opt.$layer;}catch(e){opt.$layer=null;}}
$currentTrigger=null;opt.$menu.find('.hover').trigger('contextmenu:blur');opt.$selected=null;$(document).off('.contextMenuAutoHide').off('keydown.contextMenu');opt.$menu&&opt.$menu[opt.animation.hide](opt.animation.duration,function(){if(opt.build){opt.$menu.remove();$.each(opt,function(key,value){switch(key){case'ns':case'selector':case'build':case'trigger':return true;default:opt[key]=undefined;try{delete opt[key];}catch(e){}
return true;}});}
setTimeout(function(){$trigger.trigger('contextmenu:hidden');},10);});},create:function(opt,root){if(root===undefined){root=opt;}
opt.$menu=$('<ul class="context-menu-list"></ul>').addClass(opt.className||"").data({'contextMenu':opt,'contextMenuRoot':root});$.each(['callbacks','commands','inputs'],function(i,k){opt[k]={};if(!root[k]){root[k]={};}});root.accesskeys||(root.accesskeys={});$.each(opt.items,function(key,item){var $t=$('<li class="context-menu-item"></li>').addClass(item.className||""),$label=null,$input=null;$t.on('click',$.noop);item.$node=$t.data({'contextMenu':opt,'contextMenuRoot':root,'contextMenuKey':key});if(item.accesskey){var aks=splitAccesskey(item.accesskey);for(var i=0,ak;ak=aks[i];i++){if(!root.accesskeys[ak]){root.accesskeys[ak]=item;item._name=item.name.replace(new RegExp('('+ak+')','i'),'<span class="context-menu-accesskey">$1</span>');break;}}}
if(typeof item=="string"){$t.addClass('context-menu-separator not-selectable');}else if(item.type&&types[item.type]){types[item.type].call($t,item,opt,root);$.each([opt,root],function(i,k){k.commands[key]=item;if($.isFunction(item.callback)){k.callbacks[key]=item.callback;}});}else{if(item.type=='html'){$t.addClass('context-menu-html not-selectable');}else if(item.type){$label=$('<label></label>').appendTo($t);$('<span></span>').html(item._name||item.name).appendTo($label);$t.addClass('context-menu-input');opt.hasTypes=true;$.each([opt,root],function(i,k){k.commands[key]=item;k.inputs[key]=item;});}else if(item.items){item.type='sub';}
switch(item.type){case'text':$input=$('<input type="text" value="1" name="" value="">')
.attr('name','context-menu-input-'+key)
.val(item.value||"")
.appendTo($label);break;case'textarea':$input=$('<textarea name=""></textarea>')
.attr('name','context-menu-input-'+key)
.val(item.value||"")
.appendTo($label);if(item.height){$input.height(item.height);}
break;case'checkbox':$input=$('<input type="checkbox" value="1" name="" value="">')
.attr('name','context-menu-input-'+key)
.val(item.value||"")
.prop("checked",!!item.selected)
.prependTo($label);break;case'radio':$input=$('<input type="radio" value="1" name="" value="">')
.attr('name','context-menu-input-'+item.radio)
.val(item.value||"")
.prop("checked",!!item.selected)
.prependTo($label);break;case'select':$input=$('<select name="">')
.attr('name','context-menu-input-'+key)
.appendTo($label);if(item.options){$.each(item.options,function(value,text){$('<option></option>').val(value).text(text).appendTo($input);});$input.val(item.selected);}
break;case'sub':$('<span></span>').html(item._name||item.name).appendTo($t);item.appendTo=item.$node;op.create(item,root);$t.data('contextMenu',item).addClass('context-menu-submenu');item.callback=null;break;case'html':$(item.html).appendTo($t);break;default:$.each([opt,root],function(i,k){k.commands[key]=item;if($.isFunction(item.callback)){k.callbacks[key]=item.callback;}});$('<span></span>').html(item._name||item.name||"").appendTo($t);break;}
if(item.type&&item.type!='sub'&&item.type!='html'){$input
.on('focus',handle.focusInput)
.on('blur',handle.blurInput);if(item.events){$input.on(item.events,opt);}}
if(item.icon){$t.addClass("icon icon-"+item.icon);}}
item.$input=$input;item.$label=$label;$t.appendTo(opt.$menu);if(!opt.hasTypes&&$.support.eventSelectstart){$t.on('selectstart.disableTextSelect',handle.abortevent);}});if(!opt.$node){opt.$menu.css('display','none').addClass('context-menu-root');}
opt.$menu.appendTo(opt.appendTo||document.body);},resize:function($menu,nested){$menu.css({position:'absolute',display:'block'});$menu.data('width',Math.ceil($menu.width())+1);$menu.css({position:'static',minWidth:'0px',maxWidth:'100000px'});$menu.find('> li > ul').each(function(){op.resize($(this),true);});if(!nested){$menu.find('ul').andSelf().css({position:'',display:'',minWidth:'',maxWidth:''}).width(function(){return $(this).data('width');});}},update:function(opt,root){var $trigger=this;if(root===undefined){root=opt;op.resize(opt.$menu);}
opt.$menu.children().each(function(){var $item=$(this),key=$item.data('contextMenuKey'),item=opt.items[key],disabled=($.isFunction(item.disabled)&&item.disabled.call($trigger,key,root))||item.disabled===true;$item[disabled?'addClass':'removeClass']('disabled');if(item.type){$item.find('input, select, textarea').prop('disabled',disabled);switch(item.type){case'text':case'textarea':item.$input.val(item.value||"");break;case'checkbox':case'radio':item.$input.val(item.value||"").prop('checked',!!item.selected);break;case'select':item.$input.val(item.selected||"");break;}}
if(item.$menu){op.update.call($trigger,item,root);}});},layer:function(opt,zIndex){var $layer=opt.$layer=$('<div id="context-menu-layer" style="position:fixed; z-index:'+zIndex+'; top:0; left:0; opacity: 0; filter: alpha(opacity=0); background-color: #000;"></div>')
.css({height:$win.height(),width:$win.width(),display:'block'})
.data('contextMenuRoot',opt)
.insertBefore(this)
.on('contextmenu',handle.abortevent)
.on('mousedown',handle.layerClick);if(!$.support.fixedPosition){$layer.css({'position':'absolute','height':$(document).height()});}
return $layer;}};function splitAccesskey(val){var t=val.split(/\s+/),keys=[];for(var i=0,k;k=t[i];i++){k=k[0].toUpperCase();keys.push(k);}
return keys;}
$.fn.contextMenu=function(operation){if(operation===undefined){this.first().trigger('contextmenu');}else if(operation.x&&operation.y){this.first().trigger($.Event("contextmenu",{pageX:operation.x,pageY:operation.y}));}else if(operation==="hide"){var $menu=this.data('contextMenu').$menu;$menu&&$menu.trigger('contextmenu:hide');}else if(operation==="destroy"){$.contextMenu("destroy",{context:this});}else if($.isPlainObject(operation)){operation.context=this;$.contextMenu("create",operation);}else if(operation){this.removeClass('context-menu-disabled');}else if(!operation){this.addClass('context-menu-disabled');}
return this;};$.contextMenu=function(operation,options){if(typeof operation!='string'){options=operation;operation='create';}
if(typeof options=='string'){options={selector:options};}else if(options===undefined){options={};}
var o=$.extend(true,{},defaults,options||{});var $document=$(document);var $context=$document;var _hasContext=false;if(!o.context||!o.context.length){o.context=document;}else{$context=$(o.context).first();o.context=$context.get(0);_hasContext=o.context!==document;}
switch(operation){case'create':if(!o.selector){throw new Error('No selector specified');}
if(o.selector.match(/.context-menu-(list|item|input)($|\s)/)){throw new Error('Cannot bind to selector "'+o.selector+'" as it contains a reserved className');}
if(!o.build&&(!o.items||$.isEmptyObject(o.items))){throw new Error('No Items specified');}
counter++;o.ns='.contextMenu'+counter;if(!_hasContext){namespaces[o.selector]=o.ns;}
menus[o.ns]=o;if(!o.trigger){o.trigger='right';}
if(!initialized){$document
.on({'contextmenu:hide.contextMenu':handle.hideMenu,'prevcommand.contextMenu':handle.prevItem,'nextcommand.contextMenu':handle.nextItem,'contextmenu.contextMenu':handle.abortevent,'mouseenter.contextMenu':handle.menuMouseenter,'mouseleave.contextMenu':handle.menuMouseleave},'.context-menu-list')
.on('mouseup.contextMenu','.context-menu-input',handle.inputClick)
.on({'mouseup.contextMenu':handle.itemClick,'contextmenu:focus.contextMenu':handle.focusItem,'contextmenu:blur.contextMenu':handle.blurItem,'contextmenu.contextMenu':handle.abortevent,'mouseenter.contextMenu':handle.itemMouseenter,'mouseleave.contextMenu':handle.itemMouseleave},'.context-menu-item');initialized=true;}
$context
.on('contextmenu'+o.ns,o.selector,o,handle.contextmenu);if(_hasContext){$context.on('remove'+o.ns,function(){$(this).contextMenu("destroy");});}
switch(o.trigger){case'hover':$context
.on('mouseenter'+o.ns,o.selector,o,handle.mouseenter)
.on('mouseleave'+o.ns,o.selector,o,handle.mouseleave);break;case'left':$context.on('click'+o.ns,o.selector,o,handle.click);break;}
if(!o.build){op.create(o);}
break;case'destroy':var $visibleMenu;if(_hasContext){var context=o.context;$.each(menus,function(ns,o){if(o.context!==context){return true;}
$visibleMenu=$('.context-menu-list').filter(':visible');if($visibleMenu.length&&$visibleMenu.data().contextMenuRoot.$trigger.is($(o.context).find(o.selector))){$visibleMenu.trigger('contextmenu:hide',{force:true});}
try{if(menus[o.ns].$menu){menus[o.ns].$menu.remove();}
delete menus[o.ns];}catch(e){menus[o.ns]=null;}
$(o.context).off(o.ns);return true;});}else if(!o.selector){$document.off('.contextMenu .contextMenuAutoHide');$.each(menus,function(ns,o){$(o.context).off(o.ns);});namespaces={};menus={};counter=0;initialized=false;$('#context-menu-layer, .context-menu-list').remove();}else if(namespaces[o.selector]){$visibleMenu=$('.context-menu-list').filter(':visible');if($visibleMenu.length&&$visibleMenu.data().contextMenuRoot.$trigger.is(o.selector)){$visibleMenu.trigger('contextmenu:hide',{force:true});}
try{if(menus[namespaces[o.selector]].$menu){menus[namespaces[o.selector]].$menu.remove();}
delete menus[namespaces[o.selector]];}catch(e){menus[namespaces[o.selector]]=null;}
$document.off(namespaces[o.selector]);}
break;case'html5':if((!$.support.htmlCommand&&!$.support.htmlMenuitem)||(typeof options=="boolean"&&options)){$('menu[type="context"]').each(function(){if(this.id){$.contextMenu({selector:'[contextmenu='+this.id+']',items:$.contextMenu.fromMenu(this)});}}).css('display','none');}
break;default:throw new Error('Unknown operation "'+operation+'"');}
return this;};$.contextMenu.setInputValues=function(opt,data){if(data===undefined){data={};}
$.each(opt.inputs,function(key,item){switch(item.type){case'text':case'textarea':item.value=data[key]||"";break;case'checkbox':item.selected=data[key]?true:false;break;case'radio':item.selected=(data[item.radio]||"")==item.value?true:false;break;case'select':item.selected=data[key]||"";break;}});};$.contextMenu.getInputValues=function(opt,data){if(data===undefined){data={};}
$.each(opt.inputs,function(key,item){switch(item.type){case'text':case'textarea':case'select':data[key]=item.$input.val();break;case'checkbox':data[key]=item.$input.prop('checked');break;case'radio':if(item.$input.prop('checked')){data[item.radio]=item.value;}
break;}});return data;};function inputLabel(node){return(node.id&&$('label[for="'+node.id+'"]').val())||node.name;}
function menuChildren(items,$children,counter){if(!counter){counter=0;}
$children.each(function(){var $node=$(this),node=this,nodeName=this.nodeName.toLowerCase(),label,item;if(nodeName=='label'&&$node.find('input, textarea, select').length){label=$node.text();$node=$node.children().first();node=$node.get(0);nodeName=node.nodeName.toLowerCase();}
switch(nodeName){case'menu':item={name:$node.attr('label'),items:{}};counter=menuChildren(item.items,$node.children(),counter);break;case'a':case'button':item={name:$node.text(),disabled:!!$node.attr('disabled'),callback:(function(){return function(){$node.click();};})()};break;case'menuitem':case'command':switch($node.attr('type')){case undefined:case'command':case'menuitem':item={name:$node.attr('label'),disabled:!!$node.attr('disabled'),callback:(function(){return function(){$node.click();};})()};break;case'checkbox':item={type:'checkbox',disabled:!!$node.attr('disabled'),name:$node.attr('label'),selected:!!$node.attr('checked')};break;case'radio':item={type:'radio',disabled:!!$node.attr('disabled'),name:$node.attr('label'),radio:$node.attr('radiogroup'),value:$node.attr('id'),selected:!!$node.attr('checked')};break;default:item=undefined;}
break;case'hr':item='-------';break;case'input':switch($node.attr('type')){case'text':item={type:'text',name:label||inputLabel(node),disabled:!!$node.attr('disabled'),value:$node.val()};break;case'checkbox':item={type:'checkbox',name:label||inputLabel(node),disabled:!!$node.attr('disabled'),selected:!!$node.attr('checked')};break;case'radio':item={type:'radio',name:label||inputLabel(node),disabled:!!$node.attr('disabled'),radio:!!$node.attr('name'),value:$node.val(),selected:!!$node.attr('checked')};break;default:item=undefined;break;}
break;case'select':item={type:'select',name:label||inputLabel(node),disabled:!!$node.attr('disabled'),selected:$node.val(),options:{}};$node.children().each(function(){item.options[this.value]=$(this).text();});break;case'textarea':item={type:'textarea',name:label||inputLabel(node),disabled:!!$node.attr('disabled'),value:$node.val()};break;case'label':break;default:item={type:'html',html:$node.clone(true)};break;}
if(item){counter++;items['key'+counter]=item;}});return counter;}
$.contextMenu.fromMenu=function(element){var $this=$(element),items={};menuChildren(items,$this.children());return items;};$.contextMenu.defaults=defaults;$.contextMenu.types=types;$.contextMenu.handle=handle;$.contextMenu.op=op;$.contextMenu.menus=menus;})(jQuery);