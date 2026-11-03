// 站点侦察探针：抓页面并存成 UTF-8 到 .tmp_probe/，便于用 read 工具直看结构。
// 用法：node tools/lume-probe.mjs <url> <outName> [--desktop] [--headers k:v,k:v]
import fs from 'node:fs';
import path from 'node:path';

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
const DESKTOP_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const argv = process.argv.slice(2);
const url = argv[0];
const outName = argv[1] || 'probe';
const desktop = argv.includes('--desktop');
const headerArg = argv.find((a) => a.startsWith('--headers='));
const extraHeaders = {};
if (headerArg) {
  for (const pair of headerArg.slice('--headers='.length).split(',')) {
    const at = pair.indexOf(':');
    if (at > 0) extraHeaders[pair.slice(0, at).trim()] = pair.slice(at + 1).trim();
  }
}
if (!url) {
  console.error('用法：node tools/lume-probe.mjs <url> [outName] [--desktop] [--headers=k:v,k:v]');
  process.exit(2);
}

const res = await fetch(url, {
  headers: {
    'User-Agent': desktop ? DESKTOP_UA : MOBILE_UA,
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    ...extraHeaders,
  },
  redirect: 'follow',
  signal: AbortSignal.timeout(30000),
});
const buffer = Buffer.from(await res.arrayBuffer());
// 有些站是 gbk：粗判 charset。
let text = buffer.toString('utf8');
const charset = /charset=["']?([\w-]+)/i.exec(text.slice(0, 2000))?.[1]?.toLowerCase() || '';
if (charset.includes('gb') || charset.includes('gbk') || charset.includes('big5')) {
  try {
    text = new TextDecoder('gbk').decode(buffer);
  } catch (_) {
    /* 无 gbk 解码器就用 utf8 原文 */
  }
}
fs.mkdirSync('.tmp_probe', { recursive: true });
const out = path.join('.tmp_probe', outName.endsWith('.html') ? outName : outName + '.html');
fs.writeFileSync(out, text, 'utf8');
const title = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(text)?.[1]?.trim() ?? '';
console.log(
  JSON.stringify(
    {
      url,
      finalUrl: res.url,
      status: res.status,
      charset: charset || 'utf-8',
      bytes: buffer.length,
      title: title.slice(0, 120),
      contentType: res.headers.get('content-type'),
      saved: out,
    },
    null,
    2,
  ),
);
