/// CatVod/Spider-style JS objects (including async and JSON-string replies).
/// Uses the same normalized content contract as the embedded Python adapter.
const spiderModuleAdapter = r'''
function (spider) {
  var initialized = false;
  function decoded(value) { return typeof value === 'string' ? JSON.parse(value || '{}') : (value || {}); }
  var aliases = {home:['homeContent','getHomeContent','home'], homeVod:['homeVideoContent','getHomeVideoContent','homeVod'], category:['categoryContent','getCategoryContent','category'], search:['searchContent','getSearchContent','search'], detail:['detailContent','getDetailContent','detail'], play:['playerContent','getPlayerContent','play']};
  async function invoke(name, args) {
    if (!initialized) { if (typeof spider.init === 'function') await spider.init(LumeSource.config && LumeSource.config.extend || ''); initialized = true; }
    var names = aliases[name] || [name];
    for (var key of names) if (typeof spider[key] === 'function') return decoded(await spider[key].apply(spider, args));
    throw new Error('Spider 模块缺少接口：' + name);
  }
  function items(value) { return (Array.isArray(value) ? value : value.list || []).map(function(x) {return {id:'spider:'+x.vod_id,title:x.vod_name || '',cover:x.vod_pic || '',subtitle:x.vod_remarks || ''};}); }
  async function detail(id) { var value = await invoke('detail', [[id.replace(/^spider:/,'')]]); return (value.list || [value])[0] || {}; }
  return {
    categories: async function() { var v=await invoke('home',[true]); return (v.class||[]).map(x=>({id:String(x.type_id),title:x.type_name})); },
    filters: async function(a) { var v=await invoke('home',[true]); return ((v.filters||{})[a.categoryId]||[]).map(x=>({id:x.key,title:x.name||x.key,options:(x.value||[]).map(v=>({id:String(v.v),title:String(v.n)}))})); },
    home: async function() { return items(await invoke('homeVod',[])); },
    list: async function(a) { var v = a.keyword ? await invoke('search',[a.keyword,false,a.page||1]) : a.categoryId ? await invoke('category',[a.categoryId,String(a.page||1),true,a.filters||{}]) : await invoke('homeVod',[]); return {items:items(v),hasMore:Number(v.page||a.page||1)<Number(v.pagecount||v.page_count||0)}; },
    detail: async function(a) {var v=await detail(a.id);return {id:a.id,title:v.vod_name||'',cover:v.vod_pic||'',description:v.vod_content||''};},
    chapters: async function(a) {var v=await detail(a.id),flags=String(v.vod_play_from||'').split('$$$'),out=[];String(v.vod_play_url||'').split('$$$').forEach(function(line,i){line.split('#').filter(Boolean).forEach(function(ep){var n=ep.indexOf('$');out.push({id:JSON.stringify({flag:flags[i]||'',id:n<0?ep:ep.slice(n+1)}),title:(flags.length>1?flags[i]+' · ':'')+(n<0?'播放':ep.slice(0,n))});});});return out;},
    content: async function(a) {var ep=JSON.parse(a.chapterId),v=await invoke('play',[ep.flag,ep.id,[]]);if(!v.url)throw new Error('Spider 模块未返回播放地址');return {kind:'video',url:v.url,headers:decoded(v.header||v.headers||{}),webParse:String(v.parse||0)==='1'||String(v.jx||0)==='1'};}
  };
}
''';
