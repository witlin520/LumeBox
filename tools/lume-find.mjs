// 在一份页面/脚本里按正则找线索（压缩成一行的 JS 也能用）：
// 只打印命中片段与少量上下文，避免整行刷屏。
//
// 用法：node tools/lume-find.mjs <file> '<regex>' [maxHits] [contextChars]
// 注意 PowerShell 会把参数里的双引号吃掉 —— 正则里要匹配双引号时写 \x22。
import fs from 'node:fs';

const [file, pattern, maxHitsArg, ctxArg] = process.argv.slice(2);
if (!file || !pattern) {
  console.error("用法：node tools/lume-find.mjs <file> '<regex>' [maxHits] [contextChars]");
  process.exit(2);
}
const maxHits = Number(maxHitsArg || 40);
const ctx = Number(ctxArg || 60);
const text = fs.readFileSync(file, 'utf8');
const re = new RegExp(pattern, 'g');
const seen = new Set();
let count = 0;
for (const match of text.matchAll(re)) {
  const start = Math.max(0, match.index - ctx);
  const snippet = text.slice(start, match.index + match[0].length + ctx).replace(/\s+/g, ' ');
  if (seen.has(match[0])) continue;
  seen.add(match[0]);
  console.log('· ' + snippet.slice(0, 1200));
  if (++count >= maxHits) break;
}
console.log(`\n共 ${seen.size} 个不同命中（显示 ${count}）`);
