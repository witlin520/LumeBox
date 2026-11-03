import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
const program=fs.readFileSync('assets/js/verified_page_request.js','utf8');
const request={url:'https://source.example/api/search',method:'POST',paths:['/api/search'],headers:{'x-sign':'source'},body:'{}',timeoutMs:100};
let fixture=()=>new Response('{"ok":true}',{headers:{'content-type':'application/json','set-cookie':'secret=1'}}),calls=[];
const context=vm.createContext({URL,AbortController,TextDecoder,setTimeout,clearTimeout,location:{origin:'https://source.example'},fetch:async(url,options)=>{
  calls.push({url,options});const result=fixture();Object.defineProperty(result,'url',{value:url});return result;
}});
const invoke=vm.runInContext(program,context);
const result=await invoke(request);
assert.equal(result.status,200);assert.equal(result.bodyText,'{"ok":true}');
assert.equal(result.headers['set-cookie'],undefined);
assert.equal(calls[0].options.credentials,'include');assert.equal(calls[0].options.redirect,'error');
for(const patch of [{url:'https://other.example/api/search'},{url:'https://source.example/forbidden'},{method:'DELETE'}]){
  const before=calls.length;await assert.rejects(invoke({...request,...patch}),/BRIDGE_SCOPE/);assert.equal(calls.length,before);
}
fixture=()=>new Response(new Uint8Array(1024),{headers:{'content-type':'video/mp4','content-length':'1024'}});
assert.equal((await invoke(request)).bodyText,null);
fixture=()=>new Response('x'.repeat(524289),{headers:{'content-type':'text/plain'}});
const large=await invoke(request);assert.equal(large.bodyText,null);assert.equal(large.truncated,true);
context.fetch=(url,{signal})=>new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(new Error('aborted'))));
await assert.rejects(invoke({...request,timeoutMs:5}),/aborted/);
console.log('PASS: fixed same-origin fetch, path/method gate, cookie isolation, binary/oversize handling and abort timeout');
