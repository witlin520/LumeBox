import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lume-host-test-'));
const messages = [];
let address;
const bridge = http.createServer(async (req, res) => {
  let body = ''; for await (const chunk of req) body += chunk;
  const value = JSON.parse(body || '{}'); messages.push(value);
  if (value.action === 'sourceStarted') address = value.opt.address;
  res.end('{}');
});
await new Promise(resolve => bridge.listen(0, '127.0.0.1', resolve));
fs.writeFileSync(path.join(root, 'index.js'), `module.exports.start = async () => {
  const server = catServerFactory((req,res) => {
    if (req.url === '/exit') process.exit(1);
    if (req.url === '/async') setTimeout(() => { throw new Error('fixture async error') }, 10);
    if (req.url === '/reject') Promise.reject(new Error('fixture rejection'));
    res.end('alive');
  }); server.listen(0);
};`);
fs.writeFileSync(path.join(root, 'config.js'), 'module.exports = {}');
fs.writeFileSync(path.join(root, 'spec.json'), JSON.stringify({
  bridgePort: bridge.address().port, token: 'fixture', sources: [{id: 'fixture',
    index: path.join(root, 'index.js'), config: path.join(root, 'config.js'), dataRoot: root}],
}));
const child = spawn(process.execPath, [path.resolve('assets/cat/bootstrap.js'), path.join(root, 'spec.json')],
  {stdio: ['ignore', 'ignore', 'ignore']});
try {
  const end = Date.now() + 10000;
  while (!address && Date.now() < end && child.exitCode == null) await new Promise(r => setTimeout(r, 20));
  assert.ok(address, 'source must start');
  const get = url => fetch(address + url, {signal: AbortSignal.timeout(3000)});
  assert.equal((await get('/exit')).status, 500);
  assert.equal((await get('/async')).status, 200);
  assert.equal((await get('/reject')).status, 200);
  await new Promise(r => setTimeout(r, 100));
  assert.equal(await (await get('/alive')).text(), 'alive');
  assert.equal(child.exitCode, null);
  assert.ok(messages.some(m => m.action === 'sourceError' && m.opt.message.includes('fixture async error')));
  assert.ok(messages.some(m => m.action === 'sourceError' && m.opt.message.includes('fixture rejection')));
  console.log('Cat host survives source exit, async exception and rejection; reports errors.');
} finally {
  child.kill();
  await new Promise(resolve => child.exitCode != null ? resolve() : child.once('exit', resolve));
  bridge.closeAllConnections(); await new Promise(resolve => bridge.close(resolve));
  assert.ok(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep));
  fs.rmSync(root, {recursive: true, force: true});
}
