/// Rex's synchronous storage API uses a snapshot for each invocation. Mutations
/// are flushed before returning to the host; separate runtimes merge operations.
const rexWidgetEnvironment = r'''
  var widgetState = initialState, widgetWrites = [], widgetMetadata = {};
  function widgetCopy(value) { return value == null ? null : JSON.parse(JSON.stringify(value)); }
  function widgetOwn(obj, key) { return Object.prototype.hasOwnProperty.call(obj || {}, key); }
  function widgetMap(value) { return Object.assign(Object.create(null), value || {}); }
  function widgetInstallState(value) {
    widgetState = {private:widgetMap(value.private), shared:widgetMap(value.shared), params:widgetMap(value.params), language:value.language || 'zh-CN'};
  }
  widgetInstallState(initialState);
  function widgetKey(value) {
    if (typeof value !== 'string' || !value.length || value.length > 256) throw new Error('Widget 存储键／命名空间需要 1–256 个字符');
    return value;
  }
  function widgetRead(area, key) { return widgetOwn(widgetState[area], key) ? widgetCopy(widgetState[area][key]) : null; }
  function widgetWrite(area, op, key, value, ttl) {
    if (widgetWrites.length >= 512) throw new Error('Widget 单次写入超过 512 项');
    if (op === 'clear') widgetState[area] = Object.create(null);
    else if (op === 'remove') delete widgetState[area][key];
    else widgetState[area][key] = widgetCopy(value);
    widgetWrites.push({area:area, op:op, key:key, value:widgetCopy(value), ttl:ttl});
  }
  async function widgetFlush() {
    if (!widgetWrites.length) return;
    var changes = widgetWrites.slice();
    await LumeBridge.invoke('rex.store', {operations:changes});
    widgetWrites.splice(0, changes.length);
  }
  async function widgetRun(fn) {
    await widgetFlush();
    widgetInstallState(await LumeBridge.invoke('rex.state', {}));
    try { return await fn(); } finally { await widgetFlush(); }
  }
  function widgetFunctionName(name) { return typeof name === 'string' && /^[A-Za-z_$][\w$]*$/.test(name); }
  var Widget = {
    storage: {
      get: function(key) { return widgetRead('private', widgetKey(key)); },
      set: function(key, value, ttl) { widgetWrite('private', 'set', widgetKey(key), value, ttl); },
      remove: function(key) { widgetWrite('private', 'remove', widgetKey(key)); },
      clear: function() { if(typeof Widget.__lumeClear === 'function')Widget.__lumeClear();widgetWrite('private', 'clear', ''); },
      keys: function() { return Object.keys(widgetState.private); }
    },
    sharedCache: {
      get: function(ns, key) { return widgetRead('shared', JSON.stringify([widgetKey(ns), widgetKey(key)])); },
      set: function(ns, key, value) { widgetWrite('shared', 'set', JSON.stringify([widgetKey(ns), widgetKey(key)]), value); },
      remove: function(ns, key) { widgetWrite('shared', 'remove', JSON.stringify([widgetKey(ns), widgetKey(key)])); },
      keys: function(ns) { widgetKey(ns); return Object.keys(widgetState.shared).map(function(k){try{return JSON.parse(k);}catch(_){return [];}}).filter(function(p){return p[0] === ns;}).map(function(p){return p[1];}); }
    },
    i18n: function(value) {
      if (typeof value !== 'string' || !widgetMetadata.i18n) return value;
      var lang = widgetState.language, maps = widgetMetadata.i18n;
      var table = maps[lang] || maps[lang.split('-')[0]] || {};
      return typeof table[value] === 'string' ? table[value] : value;
    },
    http: {
      request: function(options) { return LumeBridge.invoke('rex.request', options || {}); }
    },
    tmdb: {get:function(api, options){return LumeBridge.invoke('rex.tmdb',{api:api,params:options && options.params || {}});}}
  };
  ['get','post','put','delete','patch','head'].forEach(function(method) {
    Widget.http[method] = function(url, data, options) {
      if (method === 'get' || method === 'delete' || method === 'head') { options = data; data = undefined; }
      return Widget.http.request(Object.assign({}, options || {}, {url:String(url), method:method.toUpperCase()}, data === undefined ? {} : {data:data}));
    };
  });
  Widget.callSync = function(method, p) {
    p = p || {};
    var routes = {
      'storage.getItem':function(){return Widget.storage.get(p.key);},
      'storage.setItem':function(){return Widget.storage.set(p.key,p.value,p.ttl);},
      'storage.removeItem':function(){return Widget.storage.remove(p.key);},
      'storage.keys':function(){return Widget.storage.keys();},
      'storage.clear':function(){return Widget.storage.clear();},
      'sharedCache.getItem':function(){return Widget.sharedCache.get(p.namespace,p.key);},
      'sharedCache.setItem':function(){return Widget.sharedCache.set(p.namespace,p.key,p.value);},
      'sharedCache.removeItem':function(){return Widget.sharedCache.remove(p.namespace,p.key);},
      'sharedCache.keys':function(){return Widget.sharedCache.keys(p.namespace);},
      'i18n':function(){return Widget.i18n(p.value);}
    };
    if (!routes[method]) throw new Error('未实现的 Widget 同步方法：'+method);
    return routes[method]();
  };
  Widget.callAsync = function(method,p) {
    if (method === 'request') return Widget.http.request(p);
    if (method === 'tmdb') return Widget.tmdb.get(p.api,p);
    return Promise.resolve(Widget.callSync(method,p));
  };
  Widget.html = {load:function(html) {
    if (typeof HtmlDocument !== 'function') throw new Error('当前板块没有 Widget HTML 查询宿主');
    var doc = new HtmlDocument(String(html));
    function collection(nodes) {
      var result = {length:nodes.length};
      nodes.forEach(function(n,i){result[i]=n;});
      result.get=function(i){return i == null ? nodes.slice() : nodes[i < 0 ? nodes.length+i : i];};
      result.toArray=function(){return nodes.slice();};
      result.eq=function(i){var n=result.get(i);return collection(n ? [n] : []);};
      result.first=function(){return result.eq(0);}; result.last=function(){return result.eq(-1);};
      result.text=function(){return nodes.map(function(n){return n.text || '';}).join('');};
      result.html=function(){return nodes.length ? nodes[0].innerHtml : null;};
      result.attr=function(key){return nodes.length ? (nodes[0].attributes || {})[key] : undefined;};
      result.find=function(selector){return collection(nodes.flatMap(function(n){return n.querySelectorAll(selector);}));};
      result.children=function(selector){var found=collection(nodes.flatMap(function(n){return n.children || [];}));return selector ? found.filter(selector) : found;};
      result.parent=function(){return collection(Array.from(new Set(nodes.map(function(n){return n.parent;}).filter(Boolean))));};
      result.each=function(fn){nodes.forEach(function(n,i){fn.call(n,i,n);});return result;};
      result.map=function(fn){var values=nodes.map(function(n,i){return fn.call(n,i,n);});return {get:function(i){return i == null ? values : values[i];},toArray:function(){return values;}};};
      result.filter=function(test){if(typeof test === 'function')return collection(nodes.filter(function(n,i){return test.call(n,i,n);}));var allowed=doc.querySelectorAll(test);return collection(nodes.filter(function(n){return allowed.indexOf(n)>=0;}));};
      result[Symbol.iterator]=function(){return nodes[Symbol.iterator]();};
      return result;
    }
    function select(value) {
      if (value && typeof value.get === 'function') return value;
      if (typeof value === 'string') return collection(doc.querySelectorAll(value));
      return collection(value ? [value] : []);
    }
    select.root=function(){return collection(doc.querySelectorAll('html'));};
    return select;
  }};
''';

const rexWidgetAdapter = r'''
function(metadata, resolve, seed, run, state) {
  var modules = Array.isArray(metadata.modules) ? metadata.modules : [];
  var catalogs = modules.filter(function(m){return !m.type;});
  var streams = modules.filter(function(m){return m.type === 'stream';});
  if (!catalogs.length && !streams.length && !metadata.search) throw new Error('此 Widget 只提供弹幕／字幕等扩展，当前视频源入口无法导入');
  var globalParams = Array.isArray(metadata.globalParams) ? metadata.globalParams : [];
  function copyItem(value) { return JSON.parse(JSON.stringify(value)); }
  var streamResults = new Map(), detailResults = new Map();
  var privateItems = new Map(), privateChapters = new Map(), cacheDirty = false;
  var cacheKey = '__lume_rex_items';
  var hostRun = run;
  run = function(fn) { return hostRun(async function() {
    var saved=Widget.storage.get(cacheKey);
    if(Array.isArray(saved))saved.forEach(function(row){if(row && typeof row.id === 'string' && !privateItems.has(row.id))privateItems.set(row.id,row.item);});
    try { return await fn(); } finally {
      if(cacheDirty) {
        var rows=Array.from(privateItems.entries()).slice(-64).map(function(row){return {id:row[0],item:row[1]};});
        while(rows.length && JSON.stringify(rows).length>128*1024)rows.shift();
        Widget.storage.set(cacheKey,rows);cacheDirty=false;
      }
    }
  }); };
  Widget.__lumeClear = function(){privateItems.clear();privateChapters.clear();streamResults.clear();detailResults.clear();cacheDirty=false;};
  var streamSettings = streams.length && !catalogs.length ? [
    {name:'_lume_stream_type',title:'播放类型',type:'enumeration',value:'movie',enumOptions:[{title:'电影',value:'movie'},{title:'剧集',value:'tv'}]},
    {name:'_lume_stream_season',title:'季数（剧集）',type:'input',value:'1'},
    {name:'_lume_stream_episode',title:'集数（留空由脚本返回目录）',type:'input',value:''}
  ] : [];
  function defaults(params) {
    var value=Object.create(null);
    (params || []).forEach(function(p){
      if (!p || typeof p.name !== 'string') return;
      var v=p.value;
      if(v === undefined && Array.isArray(p.enumOptions) && p.enumOptions.length)v=p.enumOptions[0].value;
      if(v === undefined && p.type === 'count')v=20;
      if(v === undefined && p.type === 'page')v=1;
      if(v === undefined && p.type === 'offset')v=0;
      if(v === undefined)v='';
      value[p.name]=v;
    });
    return value;
  }
  function paramsFor(module, a) {
    a=a || {};
    var selected=Object.assign({},a.filters || {});
    Object.keys(selected).forEach(function(k){
      var value=selected[k];
      if(typeof value === 'string' && value.indexOf('rex-option:') === 0) {
        var values=value.split(',').map(function(v){return JSON.parse(decodeURIComponent(v.slice(11)));});
        selected[k]=values.length === 1 ? values[0] : values.join(',');
      }
    });
    var declared=(module.params || []), out=Object.assign(defaults(globalParams),defaults(declared),state().params,selected);
    var countParam=declared.find(function(p){return p.type === 'count';});
    var page=Math.max(1,Number(a.page)||1), count=Number(countParam ? out[countParam.name] : out.count || out.limit || 20)||20;
    declared.forEach(function(p){
      if(p.type === 'page' || p.name === 'page')out[p.name]=page;
      if(p.type === 'offset')out[p.name]=(page-1)*count+(Number(p.value)||0);
    });
    if(a.keyword) {
      out.keyword=a.keyword; out.search=a.keyword;
      declared.filter(function(p){return p.type === 'input' && /keyword|search|query|title|name|word|text|^wd$|^key$|^q$/i.test(p.name);}).forEach(function(p){out[p.name]=a.keyword;});
    }
    return out;
  }
  async function invoke(module, params) {
    if(module.requiresWebView)throw new Error('此 Widget 方法需要 Rex WebView 执行环境，当前未接通：'+module.title);
    return await resolve(module.functionName)(params);
  }
  function mediaParams(params) {
    var result={};
    ['id','tmdbId','imdbId','type','mediaType','title','seriesName','episodeName','season','episode','year','date','link','videoUrl'].forEach(function(k){if(params[k] != null)result[k]=params[k];});
    return result;
  }
  function publicItem(item,depth) {
    if(depth>8)throw new Error('Widget 条目目录超过 8 层');
    var result={};
    ['id','type','title','description','coverUrl','posterPath','posterUrl','poster_url','detailPoster','backdropPath','releaseDate','mediaType','genreTitle','durationText','videoUrl','link','season','episode','year','parent','index'].forEach(function(k){if(item[k] != null)result[k]=item[k];});
    if(item.params)result.params=mediaParams(item.params);
    ['peoples','genreItems','backdropPaths','backdropImageUrls'].forEach(function(k){if(Array.isArray(item[k]))result[k]=copyItem(item[k]);});
    if(item.rating != null)result.rating=item.rating;
    if(item.headers || item.customHeaders || item.requiresHeaders)result.requiresHeaders=true;
    ['episodeItems','childItems'].forEach(function(k){if(Array.isArray(item[k]))result[k]=item[k].map(function(x){return publicItem(x,depth+1);});});
    return result;
  }
  function pack(item) {
    var text=JSON.stringify(publicItem(item,0));
    if(text.length>32768)throw new Error('Widget 条目过大，无法保存目录身份');
    var id='rex:'+encodeURIComponent(text);
    if(item.type !== 'widget-chapter') {
      privateItems.set(id,copyItem(item));cacheDirty=true;
      if(privateItems.size>64)privateItems.delete(privateItems.keys().next().value);
    }
    return id;
  }
  function unpack(id) {
    if(typeof id !== 'string' || id.slice(0,4) !== 'rex:')throw new Error('Widget 条目身份无效');
    return privateItems.has(id) ? copyItem(privateItems.get(id)) : JSON.parse(decodeURIComponent(id.slice(4)));
  }
  function imageUrl(url) {
    return typeof url === 'string' && url.charAt(0)==='/' ? 'https://image.tmdb.org/t/p/w500'+url : url || '';
  }
  function poster(item, detail) {
    return imageUrl((detail && item.detailPoster) || item.posterPath || item.posterUrl || item.poster_url || item.backdropPath || item.coverUrl);
  }
  function backdrop(item) {return imageUrl(item.backdropPath || item.coverUrl || item.posterPath || item.posterUrl || item.poster_url);}
  function row(item) {return {id:pack(item),title:item.title || String(item.id || ''),cover:poster(item,false),coverHeaders:item.headers || {},duration:item.duration,subtitle:item.description || item.durationText || item.genreTitle || ''};}
  function listItems(value) {if(Array.isArray(value))return value;if(value && Array.isArray(value.items))return value.items;if(value && Array.isArray(value.list))return value.list;throw new Error('Widget 列表方法没有返回条目数组');}
  async function details(item) {
    if(item.type === 'widget-stream')return item;
    // URL/Forward links route to loadDetail(link), not directly to playback.
    // ID-backed metadata types must not call another module's detail handler.
    if((item.link && ['tmdb','douban','imdb'].indexOf(item.type)<0) || item.type === 'detail') {
      var key=String(item.type)+':'+String(item.link || item.id), cached=detailResults.get(key);
      if(cached && cached.expires>Date.now())return copyItem(cached.item);
      var fn;
      try {fn=resolve('loadDetail');} catch(_) {throw new Error('Widget 详情条目缺少 loadDetail 函数');}
      var value=await fn(String(item.link || item.id));
      if(Array.isArray(value))value={episodeItems:value};
      if(!value || typeof value !== 'object')throw new Error('Widget 详情没有返回条目');
      var result=Object.assign({},item,value), duration=metadata.detailCacheDuration == null ? 60 : Math.max(0,Number(metadata.detailCacheDuration)||0);
      if(duration>0){detailResults.set(key,{item:copyItem(result),expires:Date.now()+duration*1000});if(detailResults.size>64)detailResults.delete(detailResults.keys().next().value);}
      return result;
    }
    return item;
  }
  function query(keyword) {
    var p=Object.assign(defaults(globalParams),defaults(streamSettings),state().params);
    p.type=p._lume_stream_type === 'tv' ? 'tv' : 'movie';
    p.season=Math.max(1,Number(p._lume_stream_season)||1);
    if(p._lume_stream_episode !== '' && p._lume_stream_episode != null)p.episode=Math.max(1,Number(p._lume_stream_episode)||1);
    var match=keyword.match(/^(.*?)\s+[sS](\d{1,3})[eE](\d{1,4})\s*$/);
    if(match){keyword=match[1].trim();p.type='tv';p.season=Number(match[2]);p.episode=Number(match[3]);}
    p.seriesName=keyword;p.title=keyword;p.keyword=keyword;
    return p;
  }
  async function resourceLines(params) {
    var output=[],seen=Object.create(null);
    for(var module of streams) {
      var list=listItems(await invoke(module,Object.assign(paramsFor(module,{}),params)));
      for(var line of list) {
        if(!line || !line.url || seen[line.url])continue;
        seen[line.url]=true;output.push({type:'url',id:line.url,videoUrl:line.url,title:line.name || module.title || '播放',description:line.description || '',headers:line.customHeaders || line.headers || {},playerType:line.playerType,__lumeResourceParams:copyItem(params),__lumeResourceName:line.name || module.title || '播放',__lumeResourceModule:String(module.id)});
        if(output.length>=500)throw new Error('Widget 播放线路超过 500 条');
      }
    }
    return output;
  }
  async function streamChapters(item) {
    var key=pack(item), cached=streamResults.get(key);
    if(cached)return cached;
    var lines=await resourceLines(item.params || Object.assign(query(item.title || ''),{id:item.id,tmdbId:item.type === 'tmdb' ? item.id : undefined,imdbId:item.type === 'imdb' ? item.id : undefined,type:item.mediaType || 'movie',season:item.season,episode:item.episode}));
    streamResults.set(key,lines);
    if(streamResults.size>64)streamResults.delete(streamResults.keys().next().value);
    return lines;
  }
  async function chapters(item) {
    if(item.type === 'widget-stream')return await streamChapters(item);
    var value=await details(item), output=[];
    function walk(node,depth,line) {
      if(depth>8)throw new Error('Widget 剧集目录超过 8 层');
      if(output.length>=500)throw new Error('Widget 剧集超过 500 项');
      var children=node.episodeItems || node.childItems;
      if(Array.isArray(children) && children.length){children.forEach(function(x){walk(x,depth+1,depth>0 ? node.line || node.title || line : line);});return;}
      output.push(Object.assign({},node,{__lumeLine:node.line || line || ''}));
    }
    if(value.videoUrl || value.type === 'url' || value.childItems || value.episodeItems)walk(value,0,'');
    else if(streams.length)output=await streamChapters(value);
    else throw new Error('此 Widget 条目只提供影视资料，尚未提供可用播放资源');
    return output;
  }
  var source={
    id:seed.id,name:metadata.title || seed.name,version:metadata.version || seed.version,category:'video',
    widgetParameters:globalParams.concat(streamSettings),
    compatibilityWarnings:!catalogs.length && streams.length ? ['这是 Rex 播放线路模块：请用片名搜索；剧集可在源设置选择季／集，或搜索“片名 S01E02”。'] : [],
    categories:async function(){return run(async function(){return catalogs.map(function(m){return {id:String(m.id),title:Widget.i18n(m.title || m.id)};});});},
    filters:async function(a){return run(async function(){
      var module=catalogs.find(function(m){return String(m.id) === String(a && a.categoryId);}) || catalogs[0];
      if(!module)return [];
      var values=paramsFor(module,a);
      return globalParams.concat(module.params || []).filter(function(p){return p.type === 'enumeration' && (!p.belongTo || (p.belongTo.value || []).map(String).indexOf(String(values[p.belongTo.paramName]))>=0);}).map(function(p){return {id:p.name,title:Widget.i18n(p.title || p.name),options:(p.enumOptions || []).map(function(o){return {id:'rex-option:'+encodeURIComponent(JSON.stringify(o.value)),title:Widget.i18n(o.title || String(o.value))};})};});
    });},
    list:async function(a){return run(async function(){
      a=a || {};
      if(a.keyword && !metadata.search && streams.length && !catalogs.length) {
        if(Number(a.page || 1)>1)return {items:[],hasMore:false};
        var p=query(String(a.keyword)), item={type:'widget-stream',id:p.seriesName,title:p.seriesName,params:mediaParams(p)};
        var lines=await resourceLines(p);
        if(!lines.length)return {items:[],hasMore:false};
        streamResults.set(pack(item),lines);if(streamResults.size>64)streamResults.delete(streamResults.keys().next().value);
        return {items:[row(item)],hasMore:false};
      }
      var module=a.keyword ? metadata.search : catalogs.find(function(m){return String(m.id) === String(a.categoryId);}) || catalogs[0];
      if(!module)return {items:[],hasMore:false};
      var p=paramsFor(module,a),value=await invoke(module,p),items=listItems(value);
      var paged=(module.params || []).some(function(p){return p.type==='page' || p.type==='offset' || p.name==='page';});
      var countParam=(module.params || []).find(function(p){return p.type === 'count';});
      return {items:items.map(row),hasMore:typeof value.hasMore === 'boolean' ? value.hasMore : paged && items.length >= Number(countParam ? p[countParam.name] : p.count || p.limit || 20)};
    });},
    detail:async function(a){return run(async function(){var item=await details(unpack(a.id));return {
      id:a.id,title:item.title || '',cover:poster(item,true),coverHeaders:item.headers || {},backdrop:backdrop(item),
      description:item.description || '',author:item.genreTitle || '',year:String(item.releaseDate || item.year || ''),mediaType:item.mediaType || '',
      subtitle:[item.releaseDate || item.year,item.genreTitle,item.rating ? '评分 '+item.rating : ''].filter(Boolean).join(' · '),
      tags:(item.genreItems || []).map(function(g){return g.title;}).filter(Boolean),
      cast:(item.peoples || []).filter(function(p){return p && p.title;}).map(function(p){return {id:String(p.id || ''),name:p.title,avatar:imageUrl(p.avatar),role:p.role || '',headers:item.headers || {}};})
    };});},
    chapters:async function(a){return run(async function(){return (await chapters(unpack(a.id))).map(function(item,index){
      var id=pack({type:'widget-chapter',parent:a.id,index:index,title:item.title || '播放'});
      privateChapters.set(id,item);if(privateChapters.size>500)privateChapters.delete(privateChapters.keys().next().value);
      return {id:id,title:(item.title || '播放')+(item.description ? ' · '+item.description : ''),line:item.__lumeLine || (item.__lumeResourceParams ? item.__lumeResourceName : ''),cover:poster(item,false),coverHeaders:item.headers || {}};
    });});},
    content:async function(a){return run(async function(){
      var item=unpack(a.chapterId);
      if(item.type === 'widget-chapter') {
        var leaf=privateChapters.get(a.chapterId);
        if(!leaf)leaf=(await chapters(unpack(item.parent)))[item.index];
        if(!leaf)throw new Error('Widget 播放线路已变化，请重新打开目录');
        item=leaf;
      }
      if(item.__lumeResourceParams) {
        var refreshed=await resourceLines(item.__lumeResourceParams);
        var selected=refreshed.find(function(line){return line.__lumeResourceName === item.__lumeResourceName && line.__lumeResourceModule === item.__lumeResourceModule;});
        if(!selected)throw new Error('Widget 当前线路已不可用，请重新打开目录');
        item=selected;
      } else if(!item.videoUrl && !(item.type === 'url' && /^https?:\/\//i.test(item.id || '')) && streams.length) {
        var resources=await streamChapters(item);
        if(!resources.length)throw new Error('Widget 没有匹配到当前剧集资源');
        item=resources[0];
      } else if(!item.videoUrl) item=await details(item);
      if(item.requiresHeaders && !item.headers && !item.customHeaders)throw new Error('Widget 请求头缓存已失效，请重新搜索此影片');
      var url=item.videoUrl || (item.type === 'url' ? item.id : '');
      if(typeof url !== 'string' || !/^https?:\/\//i.test(url))throw new Error('Widget 未返回可直接播放的 HTTP(S) 地址');
      return {kind:'video',url:url,headers:item.customHeaders || item.headers || {}};
    });}
  };
  source.home=async function(){return (await source.list({page:1})).items;};
  return source;
}
''';
