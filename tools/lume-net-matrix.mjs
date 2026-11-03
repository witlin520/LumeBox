// 可达性矩阵：对每个源用它真正会打的 URL，分别用「直连」和「本机代理(127.0.0.1:7890)」各测一次。
// 目的：把「哪些源必须挂代理、哪些直连就行」写清楚（README 与汇报都要它）。
// 用法：node tools/lume-net-matrix.mjs
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);
const UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
const PROXY = process.env.LUME_PROXY || 'http://127.0.0.1:7890';

const targets = [
  ['播剧网 ysxq', 'https://ysxq.cc/api.php/provide/vod/?ac=list&pg=1'],
  ['A123TV', 'https://a123tv.com/t/10.html'],
  ['饭搭子 fdzys', 'https://fdzys.com/movie/all'],
  ['飞流 flixflop', 'https://www.flixflop.com/'],
  ['短剧网 duanju2', 'https://www.duanju2.com/'],
  ['欧乐 olehdtv', 'https://www.olehdtv.com/index.php/vod/show/id/1.html'],
  ['华视 huavod', 'https://huavod.com/vodtype/1.html'],
  ['懂片帝 dongpian12', 'https://dongpian12.com/'],
];

async function probe(url, proxy) {
  const args = ['-s', '-o', 'NUL', '-w', '%{http_code} %{size_download}', '--max-time', '25', '-A', UA];
  if (proxy) args.push('-x', PROXY);
  else args.push('--noproxy', '*');
  args.push(url);
  try {
    const { stdout } = await run('curl.exe', args);
    const [code, size] = stdout.trim().split(/\s+/);
    return `${code} ${size}b`;
  } catch (error) {
    return 'ERR';
  }
}

console.log('站点'.padEnd(18) + '直连'.padEnd(16) + '经代理');
for (const [label, url] of targets) {
  const direct = await probe(url, false);
  const proxied = await probe(url, true);
  console.log(label.padEnd(18) + direct.padEnd(16) + proxied);
}
