// Run: node tools/cat_runtime_smoke.mjs. All servers and account data are local fixtures.
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
const temp = fs.mkdtempSync(path.join(os.tmpdir(),'lume-cat-smoke-'));
const profiles = new Map();
const addresses = new Map();
const startupIds = new Set();
let control;
const token = 'fixture-only';
const bridge = http.createServer(async(req,res)=>{
  if (req.headers['x-catvod-token'] !== token) {res.writeHead(403);res.end();return;}
  let text=''; for await(const chunk of req) text+=chunk;
  const {action,opt={}}=JSON.parse(text);
  const id=req.headers['x-lume-cat-source'];
  if(action==='controlReady') control=opt.address;
  if(action==='sourceStarted') addresses.set(opt.id,opt.address);
  if(action==='saveProfile') profiles.set(id,opt);
  if(action==='startupProbe') startupIds.add(id);
  res.writeHead(200,{'content-type':'application/json'});
  res.end(JSON.stringify(action==='queryProfile' ? profiles.get(id)||{} : {}));
});
await new Promise(resolve=>bridge.listen(0,'127.0.0.1',resolve));
const index=path.join(temp,'index.js'), config=path.join(temp,'index.config.js');
fs.writeFileSync(index, `
const http=require('node:http');
const message=(action,opt={})=>new Promise((resolve,reject)=>{
 const req=http.request({host:'127.0.0.1',port:globalThis.catDartServerPort(),path:'/msg',method:'POST',headers:{'content-type':'application/json'}},res=>{
  let s='';res.on('data',c=>s+=c);res.on('end',()=>resolve(JSON.parse(s||'{}')));
 });req.on('error',reject);req.end(JSON.stringify({action,opt}));
});
exports.start=async()=>{
 setTimeout(()=>message('startupProbe'),80);
 const server=globalThis.catServerFactory(async(req,res)=>{
  let s='';for await(const c of req)s+=c;
  if(req.url==='/fail')throw Error('fixture failure');
  if(req.url==='/website'){res.writeHead(200,{'content-type':'text/html'});res.end('<html>Login fixture</html>');return;}
  const result=req.url==='/save'?await message('saveProfile',JSON.parse(s||'{}')):await message('queryProfile');
  res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify(result));
 });server.listen(9988);
};
`);
fs.writeFileSync(config,'module.exports={};');
const spec=id=>{const dataRoot=path.join(temp,id);fs.mkdirSync(dataRoot,{recursive:true});return{id,index,config,dataRoot};};
const specFile=path.join(temp,'spec.json');
fs.writeFileSync(specFile,JSON.stringify({token,bridgePort:bridge.address().port,sources:[spec('a'),spec('b')]}));
const child=spawn(process.execPath,[path.resolve('assets/cat/bootstrap.js'),specFile],{stdio:['ignore','ignore','pipe']});
child.stderr.on('data',()=>{});
const request=async(base,route,body,authenticated=false)=>{
 const r=await fetch(base+route,{method:body===undefined?'GET':'POST',headers:{'content-type':'application/json',...(authenticated?{'x-catvod-token':token}:{})},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(6000)});
 assert.equal(r.status,200);return r.json();
};
try{
 const begin=Date.now();while((addresses.size<2 || startupIds.size<2) && Date.now()-begin<10000)await new Promise(resolve=>setTimeout(resolve,40));
 assert.equal(addresses.size,2);assert.deepEqual([...startupIds].sort(),['a','b']);
 assert.equal((await fetch(control+'/ctl/status')).status,403);
 await request(addresses.get('a'),'/save',{cookie:'account-a'});
 await request(addresses.get('b'),'/save',{cookie:'account-b'});
 assert.equal((await request(addresses.get('a'),'/profile')).cookie,'account-a');
 assert.equal((await request(addresses.get('b'),'/profile')).cookie,'account-b');
 assert.equal((await fetch(addresses.get('a')+'/fail')).status,500);
 assert.equal((await fetch(addresses.get('a')+'/website')).headers.get('content-type'),'text/html');
 await request(control,'/ctl/stop',{id:'a'},true);
 await request(control,'/ctl/source',spec('a'),true);
 assert.equal((await request(addresses.get('a'),'/profile')).cookie,'account-a');
 await request(addresses.get('a'),'/save',{});
 assert.deepEqual(await request(addresses.get('a'),'/profile'),{});
 assert.equal((await request(addresses.get('b'),'/profile')).cookie,'account-b');
 console.log('PASS: Node control, delayed startup identity, login profile isolation/logout, config HTML, error recovery and source restart');
}finally{
 child.kill();await new Promise(resolve=>child.once('exit',resolve));
 bridge.closeAllConnections();await new Promise(resolve=>bridge.close(resolve));
 fs.rmSync(temp,{recursive:true,force:true});
}
