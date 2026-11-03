// 批量跑测 sources/video 下的图源源脚本，按「每个源实际需要的网络路径」分组执行：
//   · 直连可用的源：不加代理
//   · 只有挂代理才通的源（欧乐 / 华视）：加本机代理（默认 http://127.0.0.1:7890）
//
// 用法：node tools/check-all-sources.mjs [--keyword 片名] [--only olehdtv,huavod]
//      LUME_PROXY=http://127.0.0.1:7890 可覆盖代理地址
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);
const PROXY = process.env.LUME_PROXY || 'http://127.0.0.1:7890';

// needProxy 依据：用 App 同款 Dart HTTP 栈实测（见 .tmp_probe/dart_matrix.dart）：
// 直连 403、挂代理 200 的只有欧乐与华视。
const SOURCES = [
  { file: 'sources/video/ysxq-boju.js', name: '播剧网（ysxq）', needProxy: false, keyword: '庆余年' },
  { file: 'sources/video/a123tv.js', name: 'A123TV', needProxy: false, keyword: '寒战' },
  { file: 'sources/video/fdzys.js', name: '饭搭子影视', needProxy: false, keyword: '九门' },
  { file: 'sources/video/flixflop.js', name: '飞流视频', needProxy: false, keyword: '' },
  { file: 'sources/video/duanju2.js', name: '短剧网', needProxy: false, keyword: '儿媳' },
  { file: 'sources/video/olehdtv.js', name: '欧乐影院', needProxy: true, keyword: '空枪' },
  { file: 'sources/video/huavod.js', name: '华视影院', needProxy: true, keyword: '希望' },
  { file: 'sources/video/yue5xi5.js', name: '快猫', needProxy: false, keyword: '眼镜' },
  { file: 'sources/video/thepornjoy.js', name: 'ThePornJoy', needProxy: false, keyword: 'amateur' },
  { file: 'sources/video/haoqi7.js', name: '好妻网', needProxy: true, keyword: '学妹' },
  { file: 'sources/video/xfdxv.js', name: '41看片', needProxy: false, keyword: '视频' },
  { file: 'sources/video/spankbang.js', name: 'SpankBang', needProxy: true, keyword: 'teen' },
  { file: 'sources/video/hstv.js', name: 'HSTV', needProxy: false, keyword: '短剧' },
  { file: 'sources/video/jiuxse.js', name: '9sex', needProxy: true, keyword: '视频' },
  { file: 'sources/video/mwx43zd.js', name: '快猫镜像站', needProxy: false, keyword: '巨乳' },
  { file: 'sources/video/yuese.js', name: '月色视频', needProxy: false, keyword: '护士' },
  { file: 'sources/video/haijiao.js', name: '海角', needProxy: true, keyword: '视频' },
  { file: 'sources/video/aido8.js', name: '爱豆', needProxy: false, keyword: '巨乳' },
  { file: 'sources/video/tangtoutiao.js', name: '汤头条', needProxy: false, keyword: '巨乳' },
  { file: 'sources/video/h4dh3.js', name: 'hxc', needProxy: false, keyword: '女神' },
  { file: 'sources/video/cf3.js', name: 'Butterfly2', needProxy: false, keyword: '女神' },
  { file: 'sources/video/hentai2w.js', name: 'Hentai2W', needProxy: true, keyword: 'princess' },
];

const argv = process.argv.slice(2);
const keywordArg = argv.indexOf('--keyword') >= 0 ? argv[argv.indexOf('--keyword') + 1] : '';
const onlyArg = argv.indexOf('--only') >= 0 ? argv[argv.indexOf('--only') + 1].split(',') : null;

async function check(entry) {
  const args = ['tools/lume-source-check.mjs', entry.file, '--json'];
  const keyword = keywordArg || entry.keyword;
  if (keyword) args.push('--keyword', keyword);
  const env = { ...process.env, NODE_USE_ENV_PROXY: '1' };
  if (entry.needProxy) {
    env.HTTPS_PROXY = PROXY;
    env.HTTP_PROXY = PROXY;
  } else {
    delete env.HTTPS_PROXY;
    delete env.HTTP_PROXY;
  }
  try {
    const { stdout } = await run(process.execPath, args, { env, maxBuffer: 32 * 1024 * 1024 });
    return JSON.parse(stdout)[0];
  } catch (error) {
    try {
      return JSON.parse(error.stdout ?? '')[0];
    } catch (_) {
      return { name: entry.name, ok: false, calls: { run: { ok: false, error: error.message } } };
    }
  }
}

const rows = [];
for (const entry of SOURCES) {
  if (onlyArg && !onlyArg.some((key) => entry.file.includes(key))) continue;
  const report = await check(entry);
  const calls = report.calls ?? {};
  const playable = calls.playable
    ? calls.playable.ok
      ? calls.playable.probe && !calls.playable.probe.ok
        ? 'FAIL(地址不可播)'
        : 'ok'
      : 'FAIL'
    : 'n/a';
  rows.push({
    source: report.name || entry.name,
    proxy: entry.needProxy ? 'yes' : 'no',
    verdict: report.ok ? 'PASS' : 'FAIL',
    home: calls.home?.ok === false ? 'FAIL' : calls.home?.skipped ? '-' : calls.home?.items ?? '-',
    categories: calls.categories?.count ?? '-',
    items: calls.list?.count ?? '-',
    search: calls.search ? calls.search.count : '-',
    detail: calls.detail?.ok === false ? 'FAIL' : calls.detail?.title ? 'ok' : '-',
    chapters: calls.chapters?.count ?? '-',
    content: `${calls.content?.kind ?? '-'} ${playable}`,
  });
  process.stdout.write(`跑完 ${entry.name}\n`);
}

const widths = { source: 18, proxy: 6, verdict: 7, home: 6, categories: 11, items: 6, search: 7, detail: 7, chapters: 9, content: 22 };
const header = ['源', '代理', '结论', '首页', '分类', '条目', '搜索', '详情', '章节', '播放'];
const keys = ['source', 'proxy', 'verdict', 'home', 'categories', 'items', 'search', 'detail', 'chapters', 'content'];
const pad = (text, width) => {
  const value = String(text ?? '');
  const chars = [...value].length;
  return value + ' '.repeat(Math.max(0, width - chars));
};
console.log('\n' + keys.map((key, index) => pad(header[index], widths[key])).join(''));
for (const row of rows) {
  console.log(keys.map((key) => pad(row[key], widths[key])).join(''));
}
const failed = rows.filter((row) => row.verdict !== 'PASS');
console.log(`\n合计 ${rows.length} 个源：通过 ${rows.length - failed.length}，失败 ${failed.length}`);
process.exit(failed.length ? 1 : 0);
