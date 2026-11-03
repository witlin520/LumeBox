// 站点结构侦察：抓页面 → 给出「这是什么前端 + 可能的接口 + 内嵌 JSON」线索。
// 用法：node tools/lume-recon.mjs <url> [url...]
// 注意：直连被 WAF 拦时先设 HTTPS_PROXY + NODE_USE_ENV_PROXY=1。
import fs from 'node:fs';
import path from 'node:path';

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

const urls = process.argv.slice(2);
if (!urls.length) {
  console.error('用法：node tools/lume-recon.mjs <url> [url...]');
  process.exit(2);
}

function uniq(list, limit = 20) {
  return [...new Set(list)].slice(0, limit);
}

for (const url of urls) {
  let text = '';
  let status = 0;
  let finalUrl = url;
  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': MOBILE_UA, Accept: 'text/html,*/*;q=0.8', 'Accept-Language': 'zh-CN,zh;q=0.9' },
      redirect: 'follow',
      signal: AbortSignal.timeout(30000),
    });
    status = res.status;
    finalUrl = res.url;
    text = await res.text();
  } catch (error) {
    console.log(`### ${url}\n  请求失败：${error.message}`);
    continue;
  }

  const name = new URL(url).host.replace(/[^\w.-]/g, '_');
  fs.mkdirSync('.tmp_probe', { recursive: true });
  fs.writeFileSync(path.join('.tmp_probe', name + '.recon.html'), text, 'utf8');

  const title = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(text)?.[1]?.trim() ?? '';
  const scripts = uniq([...text.matchAll(/<script[^>]+src=["']([^"']+)["']/gi)].map((m) => m[1]));
  const apis = uniq(
    [...text.matchAll(/["'`]((?:\/|https?:\/\/[^"'`]*?)\/api\/[A-Za-z0-9_\-/.?=&%]{0,80})["'`]/g)].map((m) => m[1]),
    24,
  );
  const inlineJson = uniq(
    [...text.matchAll(/(__NEXT_DATA__|__NUXT__|__INITIAL_STATE__|window\.__[A-Z_]+__)/g)].map((m) => m[1]),
  );
  const links = uniq(
    [...text.matchAll(/href=["']([^"'#]+)["']/gi)]
      .map((m) => m[1])
      .filter((href) => /\/(vod|detail|play|show|stream|video|movie|tv|bangumi|watch|search)/i.test(href)),
    16,
  );
  const media = uniq([...text.matchAll(/https?:\/\/[^"'\\\s]+?\.(?:m3u8|mp4)(?:\?[^"'\\\s]*)?/g)].map((m) => m[0]));

  console.log(`\n### ${finalUrl}  [${status}]  ${text.length}b`);
  console.log(`  title: ${title.slice(0, 90)}`);
  if (inlineJson.length) console.log(`  内嵌状态: ${inlineJson.join(', ')}`);
  if (scripts.length) console.log(`  脚本: ${scripts.slice(0, 10).join('\n        ')}`);
  if (apis.length) console.log(`  /api 片段: ${apis.join('\n             ')}`);
  if (links.length) console.log(`  内容链接: ${links.join('  ')}`);
  if (media.length) console.log(`  直链: ${media.slice(0, 5).join('  ')}`);
  console.log(`  已存: .tmp_probe/${path.basename(name)}.recon.html`);
}
