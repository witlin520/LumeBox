import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// Run the SDK emitted by html_home_files_smoke_test.dart. No dependency copies,
// source endpoints or remote scripts are executed by this check.
const sdk = fs.readFileSync(process.argv[2] || 'build/html-home-checks/sdk.js', 'utf8');
class Storage {
  values = new Map();
  getItem(key) { return this.values.get(String(key)) ?? null; }
  setItem(key, value) { this.values.set(String(key), String(value)); }
  removeItem(key) { this.values.delete(String(key)); }
  clear() { this.values.clear(); }
}
const calls = [], events = [], css = new Map();
const context = {
  localStorage: new Storage(),
  document: { documentElement: { style: { setProperty: (key, value) => css.set(key, value) } } },
  Event: class { constructor(type) { this.type = type; } },
  CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail; } },
  dispatchEvent: event => events.push(event),
  fetch: async (url, options) => {
    const call = JSON.parse(options.body);
    calls.push(call);
    let result = true;
    if (call.method === 'request') result = { ok: true, status: 200, body: '中文响应', headers: {} };
    if (call.method === 'chrome') result = { chromeMode: call.args.mode, safeTop: call.args.mode === 'edge' ? 59 : 0 };
    return { ok: true, json: async () => call.args.url === 'fail' ? { error: 'fixture failure' } : { result } };
  },
};
context.window = context;
vm.createContext(context);
vm.runInContext(sdk, context);
assert.equal(context.localStorage.getItem('theme'), 'green');
assert.equal(context.localStorage.getItem('escaped'), '</script>');
assert.equal(events.filter(event => event.type === 'fmsdk').length, 1);
assert.equal((await context.fm.req('https://fixture.invalid/', { timeout: 16 })).body, '中文响应');
assert.equal((await context.fm.req('fail')).ok, false);
const resource = new URL(context.fm.res('https://fixture.invalid/p.png', { headers: { Referer: 'https://live.invalid/' } }));
assert.equal(resource.pathname, '/session/resource');
assert.equal(JSON.parse(resource.searchParams.get('headers')).Referer, 'https://live.invalid/');
context.__fmWebHomeInlineResolver = async () => ({ url: 'https://fixture.invalid/live.m3u8', headers: { Referer: 'live' } });
await context.fm.vodInline({ vod_name: '直播间', mark: 'HLS', episodes: [{ name: 'HLS', url: 'fallback' }] });
assert.equal(calls.at(-1).args.options.headers.Referer, 'live');
assert.equal(calls.at(-1).args.url, 'https://fixture.invalid/live.m3u8');
let resolverCalls = 0;
context.__fmWebHomeInlineResolver = async () => { resolverCalls++; throw new Error('pre-resolved media must not be resolved again'); };
await context.fm.vodInline({ title: '全城追缉', mark: '第1集', headers: { Referer: 'global', 'User-Agent': 'web-home' }, episodes: [
  { name: '第1集', url: 'opaque-first' },
  { label: '正片', active: true, url: 'opaque-id', mediaUrl: 'https://fixture.invalid/movie.m3u8', headers: { Referer: 'episode' } },
] });
assert.equal(resolverCalls, 0);
assert.equal(calls.at(-1).args.url, 'https://fixture.invalid/movie.m3u8');
assert.equal(calls.at(-1).args.title, '全城追缉');
assert.deepEqual(calls.at(-1).args.options.headers, { Referer: 'episode', 'User-Agent': 'web-home' });
delete context.__fmWebHomeInlineResolver;
await context.fm.vodInline({ title: '字符串剧集', episodes: ['https://fixture.invalid/one.mp4'] });
assert.equal(calls.at(-1).args.url, 'https://fixture.invalid/one.mp4');
await context.fm.play({ mediaUrl: 'https://fixture.invalid/object.mp4', title: '对象播放', headers: { Referer: 'object' } });
assert.equal(calls.at(-1).args.url, 'https://fixture.invalid/object.mp4');
assert.equal(calls.at(-1).args.options.headers.Referer, 'object');
await assert.rejects(context.fm.play({ title: '空地址' }), /没有可播放/);
context.__fmWebHomeInlineResolver = async () => ({ headers: {} });
const beforeInvalid = calls.length;
await assert.rejects(context.fm.vodInline({ episodes: [{ url: 'opaque-id', resolve: true }] }), /未返回媒体地址/);
assert.equal(calls.length, beforeInvalid);
context.__fmWebHomeInlineResolver = async episode => ({ url: 'https://fixture.invalid/resolved.mp4', headers: { Referer: episode.pageUrl } });
await context.fm.vodInline({ headers: { 'User-Agent': 'author' }, episodes: [{ url: 'id', pageUrl: 'https://fixture.invalid/play/1' }] });
assert.deepEqual(calls.at(-1).args.options.headers, { 'User-Agent': 'author', Referer: 'https://fixture.invalid/play/1' });
// The supplied 独狼 source calls String(url).match(/^dlv:/) in its resolver.
context.__fmWebHomeInlineResolver = async episode => {
  const ref = String(episode).match(/^dlv:\/\/duboku\/(.+)$/);
  assert.ok(ref, 'legacy resolver must receive a usable custom-scheme reference');
  assert.equal(episode.url, 'dlv://duboku/fixture');
  return 'https://fixture.invalid/duboku.m3u8';
};
await context.fm.vodInline({ vod_name: '全城追缉', mark: '正片', episodes: [
  { name: '正片', url: 'dlv://duboku/fixture', resolve: true },
] });
assert.equal(calls.at(-1).args.url, 'https://fixture.invalid/duboku.m3u8');
// Preserve the full catalog while resolving only the selected episode. The
// resolver must remain tied to this playlist even if the page changes globals.
const episodeResolves = [];
context.__fmWebHomeInlineResolver = async episode => {
  episodeResolves.push(episode.url);
  return { url: 'https://fixture.invalid/' + episode.url + '.m3u8', headers: { Referer: episode.url } };
};
await context.fm.vodInline({ vod_id: 'drama47', vod_name: '兰香如故', mark: '第12集', episodes:
  Array.from({length:47}, (_,i) => ({name:'第'+(i+1)+'集',url:'episode'+i,resolve:true,line:'新咕噜4K'})) });
const playlist = calls.at(-1).args.options.playlist;
assert.equal(playlist.episodes.length, 47);
assert.equal(playlist.selected, 11);
assert.equal(playlist.itemId, 'drama47');
assert.deepEqual(episodeResolves, ['episode11']);
context.__fmWebHomeInlineResolver = () => { throw Error('wrong resolver'); };
await context.__lumeResolveHomeEpisode(88, playlist.id, 12);
assert.deepEqual(episodeResolves, ['episode11', 'episode12']);
assert.equal(calls.at(-1).method, 'episode.result');
assert.equal(calls.at(-1).args.job, 88);
assert.equal(calls.at(-1).args.value.url, 'https://fixture.invalid/episode12.m3u8');
assert.equal(calls.at(-1).args.value.options.headers.Referer, 'episode12');
await context.__lumeResolveHomeEpisode(89, playlist.id, 100);
assert.match(calls.at(-1).args.error, /选集已失效/);
await context.fm.pan.play({ url: 'https://pan.invalid/s/abc', title: '分享', password: '1234' });
assert.equal(calls.at(-1).args.url, 'push://https://pan.invalid/s/abc');
assert.equal(calls.at(-1).args.options.password, '1234');
assert.equal((await context.fm.config()).driveCheck, false);
assert.equal((await context.fm.pan.check([{}])).results[0].state, 'uncertain');
await context.fm.cache.set('key', 'value', 'livecombo');
assert.equal(calls.at(-1).args.scope, 'livecombo');
context.localStorage.setItem('theme', 'blue');
context.localStorage.setItem('theme', 'dark');
await new Promise(resolve => setImmediate(resolve));
assert.deepEqual(calls.filter(call => call.method === 'storage.set').map(call => call.args.value), ['blue', 'dark']);
await context.fm.ui.setChrome({ mode: 'edge' });
assert.equal(context.fm.ui.getViewport().safeTop, 59);
assert.equal(css.get('--fm-chrome-mode'), 'edge');
await context.fm.ui.restoreChrome();
assert.equal(context.fm.ui.getViewport().chromeMode, 'normal');

let scripts = 0, authorResolvers = 0;
for (const file of process.argv.slice(3)) {
  const html = fs.readFileSync(file, 'utf8');
  const legacy = html.match(/async function resolveEpisode\(url\) \{[\s\S]*?window\.__fmWebHomeInlineResolver = function \(url\) \{ return resolveEpisode\(url\); \};/);
  if (legacy) {
    // Execute the supplied author's resolver entry with a deterministic platform
    // backend, without running remote scripts or fetching a real movie.
    context.DL = {};
    context.SRC = { duboku: { resolve: async ref => {
      assert.equal(ref, 'author-fixture');
      return 'https://fixture.invalid/author-resolved.m3u8';
    } } };
    vm.runInContext(legacy[0], context, { filename: file });
    await context.fm.vodInline({ vod_name: '全城追缉', mark: '正片', episodes: [
      { name: '正片', url: 'dlv://duboku/author-fixture', resolve: true },
    ] });
    assert.equal(calls.at(-1).args.url, 'https://fixture.invalid/author-resolved.m3u8');
    assert.equal(calls.at(-1).args.options.episodes, undefined);
    authorResolvers++;
  }
  for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)) {
    if (/\bsrc\s*=|type\s*=\s*["'](?:application\/json|application\/ld\+json)/i.test(match[1])) continue;
    new vm.Script(match[2], { filename: file });
    scripts++;
  }
}
console.log(JSON.stringify({ sdkContracts: 'passed', authorScriptsParsed: scripts, authorResolversChecked: authorResolvers, executedRemoteRequests: 0 }));
