(async function (request) {
  'use strict';
  const target = new URL(request.url);
  if (target.origin !== location.origin || !request.paths.includes(target.pathname) ||
      !['GET','POST'].includes(request.method)) throw new Error('BRIDGE_SCOPE');
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), request.timeoutMs);
  try {
    const response = await fetch(target.href, {method:request.method,headers:request.headers,
      body:request.method === 'POST' ? request.body : undefined,
      credentials:'include',redirect:'error',signal:controller.signal});
    if (new URL(response.url).origin !== location.origin) throw new Error('BRIDGE_REDIRECT');
    const headers = {};
    for (const key of ['content-type','content-length','cache-control']) {
      const value=response.headers.get(key); if (value !== null) headers[key]=value;
    }
    const declared = Number(response.headers.get('content-length')) || 0;
    const text = /application\/(?:[\w.+-]*\+)?json|text\/plain/i.test(headers['content-type'] || '');
    if (!text || declared > 524288) {
      await response.body?.cancel();
      return {status:response.status,headers,bodyText:null,size:declared,truncated:declared>524288,binary:!text};
    }
    if (!response.body) return {status:response.status,headers,bodyText:'',size:0};
    const reader=response.body.getReader(), decoder=new TextDecoder();
    let size=0, body='';
    while (true) {
      const chunk=await reader.read(); if (chunk.done) break;
      size+=chunk.value.byteLength;
      if (size>524288) { await reader.cancel(); return {status:response.status,headers,bodyText:null,size,truncated:true}; }
      body+=decoder.decode(chunk.value,{stream:true});
    }
    body+=decoder.decode();
    return {status:response.status,headers,bodyText:body,size,truncated:false};
  } finally { clearTimeout(timeout); }
})
