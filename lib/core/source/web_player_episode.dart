import 'dart:convert';

/// Selects exactly one visible episode button on the requested document.
/// Navigation, forms, arbitrary scripts and hidden controls are not actions.
String webPlayerEpisodeScript(Uri page, String selector) =>
    '''
(function(){
  if(location.origin+location.pathname !== ${jsonEncode(page.origin + page.path)}) return 'wrong-page';
  if(document.readyState !== 'complete') return 'waiting';
  var nodes;
  try { nodes=document.querySelectorAll(${jsonEncode(selector)}); }
  catch(_) { return 'invalid'; }
  var buttons=Array.prototype.filter.call(nodes,function(el){
    return el.tagName==='BUTTON' && el.type==='button' && !el.disabled && el.getClientRects().length>0;
  });
  if(buttons.length!==1) return 'waiting';
  buttons[0].click();
  return 'selected';
})()
''';
