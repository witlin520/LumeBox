async function browserDocument(actions, selector, purpose) {
  var a=actions||{}, pause=function(ms){return new Promise(function(r){setTimeout(r,ms);});};
  var deadline=Date.now()+4800;
  var spa=!!document.querySelector('#root,#app,#__next')&&!!document.querySelector('script[src]');
  function contentReady() {
    if(document.contentType.includes('json'))return true;
    if(purpose==='list') {
      if(document.querySelector('.video-card a[href],.module-item a[href],.manga-card a[href],.book-item a[href],.post-item a[href]'))return true;
      var works=Array.from(document.querySelectorAll('a[href] img')).filter(function(img){
        var link=img.closest('a');if(!link||img.closest('header,nav,footer'))return false;
        var path;try{path=new URL(link.href,location.href).pathname;}catch(_){return false;}
        return path!=='/'&&!/^\/(privacy|terms|featured|recommended|contact|accounts?|login|signup|tags?|categories|points|vip-info)(\/|$)/i.test(path);
      });
      // SPA navigation/promo cards can appear before the actual catalogue.
      // Wait for a real batch; a legitimate single-item list still returns at
      // the bounded deadline instead of being exported prematurely.
      return works.length >= (spa?2:1);
    }
    if(purpose==='images')return !!document.querySelector(selector||'.reading-content img,.comic-reader img,article img,main img');
    if(purpose==='chapters')return !!document.querySelector(selector||'.chapter-list a,.chapters a,.wp-manga-chapter a');
    if(purpose==='media') {
      if(document.querySelector('video[src]:not([src=""]),audio[src]:not([src=""]),source[src]:not([src=""]),.playlist a,.module-play-list a'))return true;
      if(Array.from(document.querySelectorAll('meta[property^="og:video"],meta[property^="og:audio"]')).some(function(m){return !!m.content;}))return true;
      return Array.from(document.scripts).some(function(s){return /\bplayer_\w+\s*=|["']contentUrl["']\s*:\s*["']https?:/i.test(s.textContent||'');});
    }
    return true;
  }
  // A loaded document can still be an empty SPA shell. Wait for the requested
  // content, using the same script on Windows and in the exported mobile source.
  if(purpose){var readyUntil=Date.now()+(spa&&purpose==='list'?3800:2500);while(!contentReady()&&Date.now()<readyUntil)await pause(100);}
  var scroll=Math.max(0,Math.min(3,Number(a.scroll)||0)), clicks=Math.max(0,Math.min(3,Number(a.clicks)||0));
  if(a.click) {
    for(var i=0;i<clicks;i++) {
      var button=document.querySelector(a.click);
      if(!button || button.disabled)break;
      if(button.tagName==='BUTTON' && button.type==='submit' && button.form)throw new Error('制源操作不提交表单，请选择加载更多按钮');
      button.click();await pause(350);
    }
  }
  for(var j=0;j<scroll;j++){window.scrollTo(0,document.documentElement.scrollHeight);await pause(350);}
  var wanted=a.wait||selector;
  if(wanted){var until=Math.min(deadline,Date.now()+2000);while(!document.querySelector(wanted)&&Date.now()<until)await pause(100);
    if(!document.querySelector(wanted))throw new Error('网页没有出现指定内容：'+wanted);}
  return document.contentType.includes('json')?document.body.innerText:document.documentElement.outerHTML;
}
