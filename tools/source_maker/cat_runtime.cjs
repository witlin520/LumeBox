'use strict';
const http = require('node:http');
const https = require('node:https');
async function __nodeGet(url, options, count=0) {
  if(count > 5) throw new Error('重定向过多');
  return new Promise((resolve,reject)=>{
    const req=(url.startsWith('https:') ? https : http).get(url,{headers:options && options.headers || {}},res=>{
      if(res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {res.resume();resolve(__nodeGet(new URL(res.headers.location,url).href,options,count+1));return;}
      const chunks=[];let size=0;
      res.on('data',chunk=>{size+=chunk.length;if(size>6*1024*1024)req.destroy(new Error('页面超过 6MB'));else chunks.push(chunk);});
      res.on('error',reject);
      res.on('end',()=>resolve({status:res.statusCode,body:Buffer.concat(chunks).toString('utf8')}));
    });
    req.setTimeout(15000,()=>req.destroy(new Error('上游超时')));req.on('error',reject);
  });
}
const generated = (()=>{
__SOURCE_SCRIPT__
return {source:GeneratedSource,config:C};
})();
const source=generated.source, config=generated.config;
const row=v=>({vod_id:v.id,vod_name:v.title,vod_pic:v.cover||'',vod_content:v.description||''});
module.exports.start=async function() {
  const handler=async(req,res)=>{
    try {
      let raw=''; for await(const chunk of req) {raw+=chunk; if(raw.length>131072)throw new Error('请求过大');}
      const a=raw?JSON.parse(raw):{}, path=req.url.split('?')[0], op=path.split('/').pop();let reply;
      if(path==='/config') reply={video:{sites:[{key:config.id,name:config.name,api:'/source',kind:'video',siteUrl:config.url}]}};
      else if(op==='init') reply={siteUrl:config.url};
      else if(op==='home') {const cats=await source.categories();const list=await source.list({page:1});const groups=(await source.filters()).groups||[];const filters={};for(const c of cats)filters[c.id]=groups.map(g=>({key:g.id,name:g.title,value:g.options.map(o=>({v:o.id,n:o.title}))}));reply={class:cats.map(v=>({type_id:v.id,type_name:v.title})),filters,list:list.items.map(row)};}
      else if(['category','search','homeVod','homeVideo'].includes(op)) {const page=Number(a.page||a.pg||1),v=await source.list({page,keyword:a.wd||'',categoryId:a.tid||a.id||'',filters:a.filters||a.extend||{}});reply={list:v.items.map(row),page,pagecount:v.hasMore?page+1:page};}
      else if(op==='detail') {const v=await source.detail({id:a.id}),eps=await source.chapters({id:a.id});reply={list:[{...row(v),vod_play_from:'默认线路',vod_play_url:eps.map(e=>e.title.replace(/[$#]/g,' ')+'$'+encodeURIComponent(e.id)).join('#')}]};}
      else if(op==='play') {const v=await source.content({id:'',chapterId:decodeURIComponent(a.id)});reply={url:v.url,header:v.headers||{},parse:0};}
      else {res.writeHead(404,{'Content-Type':'application/json'});res.end('{}');return;}
      res.writeHead(200,{'Content-Type':'application/json; charset=utf-8'});res.end(JSON.stringify(reply));
    } catch(e) {res.writeHead(500,{'Content-Type':'application/json'});res.end(JSON.stringify({error:String(e.message||e)}));}
  };
  const server=typeof globalThis.catServerFactory==='function'?globalThis.catServerFactory(handler):http.createServer(handler);
  await new Promise(resolve=>server.listen({host:'127.0.0.1',port:0},resolve));
  return server;
};
