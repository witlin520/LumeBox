// Probe list thumbnails only for ordinary movie/audio adapters; never play media.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const [root, output, only] = process.argv.slice(2);
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'metadata/catalog.json'), 'utf8'));
const rows = catalog.sources.filter(r => ['movie', 'audiobook'].includes(r.kind) && r.rating !== '18+' && (!only || only.split(',').includes(r.id)));
async function probe(row) {
  const abort = new AbortController();
  const signal = () => AbortSignal.any([abort.signal, AbortSignal.timeout(8000)]);
  const result = { id: row.id, path: row.path, covers: [] };
  let timer;
  try {
    await Promise.race([
      (async () => {
        const context = vm.createContext({ console: { log() {}, warn() {}, error() {} }, URL, Buffer,
          TextEncoder, TextDecoder, atob, btoa });
        vm.runInContext(fs.readFileSync(path.join(root, row.path), 'utf8'), context, { timeout: 3000 });
        const source = context.LumeSource;
        const request = async (url, options = {}, method = 'GET', body) => {
          const response = await fetch(url, { method, body, signal: signal(),
            headers: { 'User-Agent': 'Mozilla/5.0', ...options.headers } });
          const text = await response.text();
          return { status: response.status, body: text, json: () => JSON.parse(text), url: response.url,
            headers: Object.fromEntries(response.headers) };
        };
        source.http = { get: request, post: (u, b, o) => request(u, o, 'POST', b) };
        const list = await source.list({ page: 1 });
        const items = Array.isArray(list) ? list : list.items || [];
        result.items = items.length;
        result.withCover = items.filter(i => i.cover).length;
        for (const item of items.filter(i => i.cover).slice(0, 3)) {
          try {
            const response = await fetch(item.cover, { signal: signal(), headers: {
              'User-Agent': 'Mozilla/5.0', ...item.coverHeaders,
            } });
            const reader = response.body?.getReader();
            const first = reader ? await reader.read() : null;
            await reader?.cancel();
            const data = Buffer.from(first?.value || []);
            const image = data.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) ||
              data[0] === 255 && data[1] === 216 || data.subarray(0,3).toString() === 'GIF' ||
              data.subarray(0,4).toString() === 'RIFF';
            result.covers.push({ status: response.status, image, host: new URL(response.url).host });
          } catch (error) { result.covers.push({ error: error.name }); }
        }
        result.status = items.length ? 'checked' : 'empty-list';
      })(),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('source-timeout')), 25000); }),
    ]);
  } catch (error) { result.status = 'failed'; result.error = error.name + ': ' + error.message.slice(0, 120); }
  finally { clearTimeout(timer); abort.abort(); }
  console.log(JSON.stringify(result));
  return result;
}
const results = [];
for (let i = 0; i < rows.length; i += 3) results.push(...await Promise.all(rows.slice(i, i + 3).map(probe)));
fs.writeFileSync(output, JSON.stringify({ sources: results }, null, 2));
