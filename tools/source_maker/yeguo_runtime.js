// Public website API envelope; no account token or desktop session is exported.
var C=__CONFIG__,ygDevice='',ygKnown={},ygSchemaPromise=null;
function ygBase(){return (LumeSource.config&&LumeSource.config.domain||C.url).replace(/\/+$/,'');}
function ygId(value){var m=/\/drama\/(?:detail|video)\/(\d+)/.exec(String(value))||/^(\d+)$/.exec(String(value));if(!m)throw new Error('作品 ID 无效');return m[1];}
function ygRemember(row){ygKnown[row.id]=row;var ids=Object.keys(ygKnown);while(ids.length>100)delete ygKnown[ids.shift()];return row;}
async function ygApi(path,args){
  if(!ygDevice){try{ygDevice=await LumeSource.fs.readText('public-device.txt');}catch(_){}if(!/^[a-f0-9]{32}$/.test(ygDevice||'')){ygDevice='';for(var i=0;i<32;i++)ygDevice+=Math.floor(Math.random()*16).toString(16);try{await LumeSource.fs.writeText('public-device.txt',ygDevice);}catch(_){}}}
  var fields={bundleId:'com.pwa.mater',version:'1.3.2',oauth_type:'web',language:'zh',via:'pwa',oauth_id:ygDevice,trace_id:ygDevice,token:''};
  Object.keys(args||{}).forEach(function(k){fields[k]=args[k];});
  var body=Object.keys(fields).map(function(k){return encodeURIComponent(k)+'='+encodeURIComponent(String(fields[k]));}).join('&');
  var r=await LumeSource.http.post(C.api+path,body,{headers:{'Content-Type':'application/x-www-form-urlencoded',Referer:ygBase()+'/'}});
  if(r.status===401)throw new Error('需要登录：请打开源站');
  if(r.status===403)throw new Error('NEED_WEBVIEW_VERIFY：站点需要网页验证');
  if(r.status<200||r.status>=300)throw new Error('接口 HTTP '+r.status);
  var envelope=JSON.parse(r.body),data=envelope;
  if(typeof envelope.data==='string'){
    var tools=LumeSource.tools;
    var raw=await tools.aes({data:envelope.data.replace(/ /g,'+'),key:await tools.base64Encode('2acf7e91e9864673'),iv:await tools.base64Encode('1c29882d3ddfcfd6'),mode:'CBC',encrypt:false});
    data=JSON.parse(await tools.base64Decode(raw));
  }
  if(Number(data.status)!==1)throw new Error(String(data.msg||data.message||'站点接口返回异常'));
  return data.data||{};
}
function ygCoverHeaders(){return {Referer:ygBase()+'/', 'x-lume-image-encoding':'aes-cbc-pkcs7','x-lume-image-key':'f5d965df75336270','x-lume-image-iv':'97b60394abc2fbe1'};}
async function ygSchema(){if(!ygSchemaPromise)ygSchemaPromise=ygApi('/api/theater/exploreList',{page:1,limit:20}).then(function(x){return x.filters||[];}).catch(function(e){ygSchemaPromise=null;throw e;});return await ygSchemaPromise;}
function ygItem(x){return ygRemember({id:String(x.video_id),title:String(x.title||''),cover:String(x.cover||''),coverHeaders:ygCoverHeaders(),subtitle:String(x.serialize_status_text||'')});}
var LumeSource={id:C.id,name:C.name,version:C.version||'1.0.2',category:'video',
  categories:async function(){var schema=await ygSchema(),theme=schema.filter(function(g){return g.key==='theme';})[0];return [{id:'all',title:'全部短剧'}].concat((theme&&theme.options||[]).map(function(o){return {id:'theme:'+o.value,title:String(o.name)};}));},
  filters:async function(){return {groups:(await ygSchema()).filter(function(g){return g.key!=='theme';}).map(function(g){return {id:g.key,title:String(g.title),options:[{id:'',title:'全部'}].concat((g.options||[]).map(function(o){return {id:String(o.value),title:String(o.name)};}))};})};},
  list:async function(a){a=a||{};if(a.keyword)throw new Error('本站关键词搜索尚未适配，请使用分类浏览或源站搜索');var page=Math.max(1,Number(a.page)||1),args={page:page,limit:20},schema=await ygSchema();
    Object.keys(a.filters||{}).forEach(function(k){var value=String(a.filters[k]||''),group=schema.filter(function(g){return g.key===k;})[0];if(!group||value&&!group.options.some(function(o){return String(o.value)===value;}))throw new Error('未支持的筛选值：'+k);if(value)args[k]=Number(value);});
    var category=String(a.categoryId||'all');if(category!=='all'){var m=/^theme:(\d+)$/.exec(category);if(!m)throw new Error('分类无效');args.theme=Number(m[1]);}
    var data=await ygApi('/api/theater/exploreList',args);if(!Array.isArray(data.list))throw new Error('列表格式不正确');return {items:data.list.filter(function(x){return x.video_id!=null&&x.title;}).map(ygItem),hasMore:typeof data.total==='number'?page*20<data.total:data.list.length>=20};},
  home:async function(){return (await LumeSource.list({page:1})).items;},
  detail:async function(a){var id=ygId(a.id),x=await ygApi('/api/playlet/detail',{video_id:id,episode_id:0,related_limit:0});var row=ygItem(x);row.id=id;row.description=String(x.description||'');row.episodes=x.episodes||[];return ygRemember(row);},
  chapters:async function(a){var row=await LumeSource.detail(a);return row.episodes.map(function(e,i){var number=Number(e.sort)||i+1;return {id:String(e.id)+':'+number,title:'第'+number+'集'+(e.access&&e.access.can_play===false?'（源站权限限制）':'')};});},
  content:async function(a){var id=ygId(a.id),m=/^(\d+):(\d+)$/.exec(String(a.chapterId||''));if(!m)throw new Error('选集编号无效，请重新打开详情');var x=await ygApi('/api/playlet/play',{video_id:id,episode_id:m[1]});var url=String(x.video_url||'');if(!(x.access&&x.access.can_play===false)&&/^https?:\/\//i.test(url))return {kind:'video',url:url,headers:{Referer:ygBase()+'/'}};return {kind:'webplayer',pageUrl:ygBase()+'/drama/video/'+id+'/ep-'+m[2]+'/',headers:{Referer:ygBase()+'/'}};}
};
