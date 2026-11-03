// Offline contract tests: node --test tool/zhilian_source_test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const script = fs.readFileSync(new URL('../sources/video/zhilian-duanju.js', import.meta.url), 'utf8');
function source({ stale = false, denied = false } = {}) {
  const calls = [], files = new Map();
  let logins = 0, expired = stale;
  const context = vm.createContext({});
  vm.runInContext(script, context);
  const api = context.LumeSource;
  api.fs = { readText: async p => files.get(p) || '', writeText: async (p, v) => files.set(p, v) };
  api.config = {};
  api.http = {
    post: async (url, raw, options) => {
      calls.push(url); logins++;
      assert.equal(new URL(url).pathname, '/api/v1/auth/guest');
      const body = JSON.parse(raw);
      assert.match(body.requestKey, /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/);
      assert.equal(body.automatic, true);
      assert.equal(options.headers['X-Client-Platform'], 'huangguo-h5');
      return { status: 200, body: JSON.stringify({ token: `header.${Buffer.from(JSON.stringify({exp: Math.floor(Date.now()/1000)+604800})).toString('base64url')}.token-${logins}` }) };
    },
    request: async options => {
      calls.push(options.url);
      assert.match(options.headers.Authorization, /^Bearer /);
      assert.ok(options.headers['X-Device-Id']);
      if (expired) { expired = false; return {status:401, body:'{}'}; }
      if (denied) return {status:403, body:'{}'};
      const url = new URL(options.url);
      const path = url.pathname;
      let data;
      if (/\/episodes\/\d+$/.test(path)) {
        const locked = path.endsWith('/2');
        data = {episode: {id: locked ? 12 : 11, number: locked ? 2 : 1, locked,
          video_url: locked ? '' : 'https://media.example/free.m3u8?token=granted'}};
      } else if (path.endsWith('/episodes')) data = {list:[{id:11,number:1,title:'第一集',access_type:'free'}, {id:12,number:2,title:'第二集',locked:true,access_type:'paid'}]};
      else if (/\/dramas\/\d+$/.test(path)) data = {drama:{id:7,title:'短剧',cover:'/cover.jpg'},episodes:[]};
      else if (path.endsWith('/home')) data = {categories:[{id:3,name:'都市'}],hot:[],latest:[],recommend:[]};
      else { assert.equal(url.searchParams.get('page'), '1'); data = {list:[{id:7,title:'短剧',cover:'/cover.jpg'}],total:1}; }
      return {status:200,body:JSON.stringify({data})};
    },
  };
  return {api,calls,files,get logins(){return logins;}};
}

test('guest session, lists, detail and free playback use granted API URL', async () => {
  const s = source();
  await Promise.all([s.api.categories(),s.api.list({page:1})]);
  assert.equal(s.logins,1);
  assert.equal((await s.api.detail({id:'7'})).title,'短剧');
  const chapters=await s.api.chapters({id:'7'});
  assert.equal(chapters[0].id,'1:11');
  const content=await s.api.content({id:'7',chapterId:chapters[0].id});
  assert.equal(content.kind,'video');
  assert.equal(content.url,'https://media.example/free.m3u8?token=granted');
  assert.equal(content.headers.Authorization,undefined);
  assert.equal(s.logins,1);
});
test('locked episode returns the site player without requesting other episodes', async () => {
  const s = source();
  const content=await s.api.content({id:'7',chapterId:'2:12'});
  assert.equal(content.kind,'webplayer');
  assert.equal(content.pageUrl,'https://yklyo880.lldj1.xyz/play/7/2');
  assert.equal(s.calls.length,2);
  assert.ok(!s.files.has('signatures.json'));
});
test('401 renews the same guest identity and retry succeeds', async () => {
  const s=source({stale:true});
  const result=await s.api.content({id:'7',chapterId:'1:11'});
  assert.equal(result.kind,'video');
  assert.equal(s.logins,2);
});
test('verification failures and invalid episodes stay actionable', async () => {
  const s=source({denied:true});
  await assert.rejects(s.api.detail({id:'7'}), /NEED_WEBVIEW_VERIFY/);
  await assert.rejects(s.api.content({id:'7',chapterId:'invalid'}), /选集编号/);
});
