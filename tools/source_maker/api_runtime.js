// Public CMS interfaces. No desktop browser session or credentials are exported.
var C=__CONFIG__, apiKnown={}, apiCursors={}, apiTaxonomy=null;
function apiAbs(value,base){if(!value)return '';value=String(value).trim();base=base||C.url;if(/^[a-z][\w+.-]*:/i.test(value)&&!/^https?:\/\//i.test(value))return '';if(/^https?:\/\//i.test(value))return value;if(value.slice(0,2)==='//')return base.split(':')[0]+':'+value;var root=/^https?:\/\/[^/]+/i.exec(base);if(!root)return '';if(value[0]==='?')return base.split(/[?#]/)[0]+value;var path=value[0]==='/'?value:base.split(/[?#]/)[0].slice(root[0].length).replace(/\/[^/]*$/,'/')+value,parts=[];path.split('/').forEach(function(p){if(p==='..')parts.pop();else if(p!=='.')parts.push(p);});return root[0]+(parts[0]===''?'':'/')+parts.join('/');}
function apiQuery(values){return Object.keys(values).filter(function(k){return values[k]!==''&&values[k]!==null&&values[k]!==undefined;}).map(function(k){return encodeURIComponent(k)+'='+encodeURIComponent(String(values[k]));}).join('&');}
function apiPlain(value){return String(value||'').replace(/<[^>]+>/g,' ').replace(/&amp;/g,'&').replace(/&#0*39;/g,"'").replace(/&quot;/g,'"').replace(/\s+/g,' ').trim();}
function apiURL(path,params){
  var split=C.api.split('#')[0].split('?'),base=split[0],query=Object.create(null);
  (split[1]||'').split('&').filter(Boolean).forEach(function(pair){var at=pair.indexOf('='),key=decodeURIComponent((at<0?pair:pair.slice(0,at)).replace(/\+/g,' ')),value=at<0?'':decodeURIComponent(pair.slice(at+1).replace(/\+/g,' '));query[key]=value;});
  if(Object.prototype.hasOwnProperty.call(query,'rest_route'))query.rest_route=query.rest_route.replace(/\/$/,'')+path;
  else base=base.replace(/\/$/,'')+path;
  Object.keys(params||{}).forEach(function(k){query[k]=params[k];});
  var encoded=apiQuery(query);return base+(encoded?'?'+encoded:'');
}
async function apiRead(path,params){
  var r=await LumeSource.http.get(apiURL(path,params),{headers:{Referer:C.url}}),data;
  if(r.status===401||r.status===403)throw new Error('接口需要登录或网页验证；请在 App 中完成验证后重试');
  if(r.status<200||r.status>=300){
    if(C.mode==='wordpress'&&path==='/posts'&&params&&params.page>1&&r.status===400){try{data=JSON.parse(r.body);if(data.code==='rest_post_invalid_page')return [];}catch(_){} }
    throw new Error('站点接口返回 HTTP '+r.status);
  }
  data=JSON.parse(r.body);
  if(C.mode==='wordpress'&&Array.isArray(data))Object.keys(r.headers||{}).forEach(function(k){if(k.toLowerCase()==='x-wp-totalpages'){var count=Number(r.headers[k]);if(Number.isInteger(count)&&count>=0)data._lumeTotalPages=count;}});
  return data;
}
function apiRemember(row){apiKnown[row.id]=row;var keys=Object.keys(apiKnown);while(keys.length>150)delete apiKnown[keys.shift()];return row;}
function apiItem(x){
  var wp=C.mode==='wordpress',featured=wp&&x._embedded&&x._embedded['wp:featuredmedia'],cover=wp?(featured&&featured[0]&&featured[0].source_url):x.thumbnail_url;
  var id=wp?String(x.id):apiAbs(x.url)||C.url.replace(/\/$/,'')+'/view?m='+encodeURIComponent(x.friendly_token);
  var row={id:id,pageUrl:wp?(apiAbs(x.link)||C.url):id,title:apiPlain(wp?x.title.rendered:x.title),cover:apiAbs(cover),coverHeaders:{Referer:C.url},subtitle:x.duration?Math.round(x.duration/60)+' 分钟':'',duration:x.duration||0,apiToken:wp?String(x.id):x.friendly_token||'',description:apiPlain(wp?(x.content&&x.content.rendered):x.description)};
  return apiRemember(row);
}
async function apiCategories(){
  var data=await apiRead('/categories',C.mode==='wordpress'?{per_page:100,hide_empty:true}:null);
  if(!Array.isArray(data))throw new Error('分类接口返回格式不正确');
  apiTaxonomy=data;return [{id:'all',title:'全部'}].concat(data.filter(function(x){return x.title||x.name;}).map(function(x){return {id:'category:'+String(C.mode==='wordpress'?x.id:x.title),title:apiPlain(x.title||x.name),itemCount:x.media_count===undefined?x.count:x.media_count};}));
}
function apiFilters(){
  var groups=[{id:'sort_by',title:'排序',options:[{id:'',title:'默认最新'},{id:'views_desc',title:'最多播放'},{id:'likes_desc',title:'最多点赞'}]}];
  if(C.mode==='wordpress')groups[0].options=[{id:'',title:'最新'},{id:'oldest',title:'最早'},{id:'title',title:'标题'}];
  else groups.push({id:'duration',title:'时长',options:[{id:'',title:'全部'},{id:'0-20',title:'20 分钟以内'},{id:'20-40',title:'20–40 分钟'},{id:'40-60',title:'40–60 分钟'},{id:'60-120',title:'60 分钟以上'}]},
    {id:'upload_date',title:'发布时间',options:[{id:'',title:'全部'},{id:'today',title:'今天'},{id:'this_week',title:'最近一周'},{id:'this_month',title:'本月'},{id:'this_year',title:'今年'}]});
  return {groups:groups};
}
function apiDurationMatches(value,range){if(!range)return true;var pair=range.split('-').map(Number),seconds=Number(value);return seconds>=pair[0]*60&&(range==='60-120'||seconds<pair[1]*60);}
async function apiList(a){
  a=a||{};var f=a.filters||{},schema=apiFilters().groups;
  Object.keys(f).forEach(function(key){var group=schema.filter(function(g){return g.id===key;})[0];if(!group||!group.options.some(function(o){return o.id===f[key];}))throw new Error('未支持的筛选值：'+key);});
  var category=String(a.categoryId||'all');if(category!=='all'&&category.indexOf('category:')!==0)throw new Error('未识别的分类');
  var page=Math.max(1,Number(a.page)||1),wp=C.mode==='wordpress',isSearch=!wp&&(a.keyword||category!=='all');
  var cursorKey=JSON.stringify([category,a.keyword||'',f]),serverPage=(apiCursors[cursorKey]||{})[page]||page;
  var result=[],hasMore=false,data,loops=0;
  do {
    var params=wp?{page:serverPage,per_page:20,_embed:1,search:a.keyword||'',categories:category==='all'?'':category.slice(9),orderby:f.sort_by==='title'?'title':'date',order:f.sort_by==='oldest'?'asc':'desc'}:
      {page:serverPage,media_type:C.media==='audio'?'audio':'video',q:a.keyword||'',c:category==='all'?'':category.slice(9),sort_by:f.sort_by||'',upload_date:f.upload_date||'',duration:isSearch?'':f.duration||''};
    data=await apiRead(wp?'/posts':isSearch?'/search':'/media',params);
    var rows=wp?data:data.results;if(!Array.isArray(rows))throw new Error('列表接口没有返回作品数组');
    hasMore=wp?(typeof data._lumeTotalPages==='number'?serverPage<data._lumeTotalPages:rows.length===20):!!data.next;
    rows.forEach(function(x){if(!isSearch||apiDurationMatches(x.duration,f.duration))result.push(apiItem(x));});
    serverPage++;loops++;
  } while(isSearch&&f.duration&&!result.length&&hasMore&&loops<5);
  if(!apiCursors[cursorKey]){if(Object.keys(apiCursors).length>=12)apiCursors={};apiCursors[cursorKey]={};}apiCursors[cursorKey][page+1]=serverPage;
  return {items:result,hasMore:hasMore};
}
async function apiDetail(id){
  var wp=C.mode==='wordpress',token=wp?String(id):(apiKnown[id]&&apiKnown[id].apiToken)||(/[?&]m=([^&#]+)/.exec(id)||[])[1];
  if(!token)throw new Error('作品缺少可验证的接口标识');
  var x=await apiRead(wp?'/posts/'+encodeURIComponent(token):'/media/'+encodeURIComponent(token),wp?{_embed:1}:null);
  var row=apiItem(x);row.id=id;row.apiToken=token;row.raw=x;return apiRemember(row);
}
function apiMediaChoices(row){
  var x=row.raw||{},choices=[];
  function add(url,label,height){url=apiAbs(url,row.pageUrl||C.url);if(url&&!choices.some(function(q){return q.url===url;}))choices.push({url:url,label:label||'原画',height:Number(height)||0,headers:{Referer:row.pageUrl||row.id}});}
  if(C.mode==='wordpress'){
    var h=x.content&&x.content.rendered||'',re=/<(?:video|audio|source)\b[^>]*\bsrc=["']([^"']+)["']/gi,m;while((m=re.exec(h)))add(m[1],'默认',0);
  }else{
    Object.keys(x.encodings_info||{}).forEach(function(height){Object.keys(x.encodings_info[height]||{}).forEach(function(codec){var v=x.encodings_info[height][codec];if(v&&v.url&&(!v.status||v.status==='success'||v.status==='completed'))add(v.url,height==='0-original'?'原画':height+'P',height);});});
    if(x.hls_info){if(x.hls_info.url)add(x.hls_info.url,'HLS',0);else Object.keys(x.hls_info).forEach(function(k){var v=x.hls_info[k];if(v&&v.url)add(v.url,k,0);});}
    if(!choices.length)add(x.original_media_url,'原画',0);
  }
  choices.sort(function(a,b){return b.height-a.height;});return choices;
}
var LumeSource = {id:C.id,name:C.name,version:C.version||'1.0.0',category:C.category,
  categories:apiCategories,filters:async function(){return apiFilters();},home:async function(){return (await apiList({page:1})).items;},list:apiList,
  detail:async function(a){return apiDetail(a.id);},
  chapters:async function(a){var row=await apiDetail(a.id);if(!apiMediaChoices(row).length)throw new Error('作品没有公开音视频编码；可能尚未转码或需要站点适配');return [{id:a.id,title:'正片'}];},
  content:async function(a){var row=await apiDetail(a.id),choices=apiMediaChoices(row);if(!choices.length)throw new Error('站点未提供公开媒体地址');return {kind:C.media==='audio'?'audio':'video',url:choices[0].url,headers:choices[0].headers,qualities:choices};}
};
