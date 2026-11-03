'use strict'
/**
 * bootstrap.js —— 「通用接口」(Node 内置源) 的宿主引导脚本
 *
 * 这是**启动契约**的实现，协议来源：FongMi `nodejs/src/main/assets/nodejs/bootstrap.js`
 * （Apple 平台的等价实现见 OKVideoMac `NodeBundleRuntimeService.swift`）。
 *
 * 用法 A（单源，兼容老调用方：桌面工具、p2-selftest）:
 *   node bootstrap.js <index.js> <index.config.js> <dataRoot> <bridgePort> <token>
 *        argv[2]        argv[3]              argv[4]     argv[5]       argv[6]
 *
 * 用法 B（多源 + 运行期控制，App 用这个）:
 *   node bootstrap.js <spec.json>
 *        spec.json = {
 *          bridgePort, token,
 *          sources: [ { id, index, config, dataRoot } ]   // 可以一次给多个
 *        }
 *
 * 它做七件事：
 *   1. 设置 bundle 约定的环境变量（停用自启动，改由宿主提供 server 工厂）
 *   2. 注入 globalThis.catServerFactory / catDartServerPort —— **每个源一份，互不串台**
 *   3. 给 http.request 打补丁：访问宿主 /msg 桥时自动带 X-CatVod-Token
 *   4. 每个源单独回报 sourceStarted / sourceError（老的单源回报 serverStarted 照旧发）
 *   5. 每个本地服务**各自**带"监听自愈"（iOS 挂起后 socket 被回收 → 原地重绑）
 *   6. 逐个 require(index.config.js) + require(index.js) 并 await runtime.start(config)
 *   7. 开一个**控制口**（只有这段我们自己的代码，不碰第三方）：
 *        GET  /ctl/status              → { ok, pid, sources:[{id, address, listening}] }
 *        POST /ctl/source {spec}       → 运行期**追加**一个源（换源/新开一个源不用重启 App）
 *        POST /ctl/stop   {id}         → 关掉某个源的本地服务（下次启动才彻底释放内存）
 *      为什么要它：iOS 上 node_start 不可重入，一个进程只能起一次 Node；
 *      但只要 Node 活着，我们就可以在**同一个进程里**再 start 一个 bundle，
 *      这样"切换源"就是秒切，而不是"关掉 App 再开"。
 */

const http = require('node:http')
const net = require('node:net')
const fs = require('node:fs')
const path = require('node:path')
const { pathToFileURL } = require('node:url')

const TOKEN_HEADER = 'X-CatVod-Token'

// ------------------------------------------------------------------ 参数解析
const argv = process.argv.slice(2)
const sourceContext = new (require('node:async_hooks').AsyncLocalStorage)()

function parseSpec() {
  const first = argv[0] || ''
  // 用法 B：第一个参数是 .json → 多源 spec
  if (/\.json$/i.test(first) && fs.existsSync(first)) {
    const raw = JSON.parse(fs.readFileSync(first, 'utf8'))
    const sources = Array.isArray(raw.sources) ? raw.sources : []
    return {
      bridgePort: Number(raw.bridgePort),
      token: String(raw.token || ''),
      sources: sources
        .filter((s) => s && s.index && s.config && s.dataRoot)
        .map((s) => ({
          id: String(s.id || path.basename(path.dirname(s.index)) || 'source'),
          index: path.resolve(String(s.index)),
          config: path.resolve(String(s.config)),
          dataRoot: path.resolve(String(s.dataRoot)),
        })),
    }
  }
  // 用法 A：老的单源形式
  const [, , indexPath, configPath, dataRoot, bridgePortText, token] = process.argv
  return {
    bridgePort: Number(bridgePortText),
    token: String(token || ''),
    sources: indexPath && configPath && dataRoot
      ? [{ id: 'default', index: path.resolve(indexPath), config: path.resolve(configPath), dataRoot: path.resolve(dataRoot) }]
      : [],
  }
}

let spec
try {
  spec = parseSpec()
} catch (error) {
  console.error(`[bootstrap] spec 解析失败：${error && error.message}`)
  process.exit(2)
}

const bridgePort = spec.bridgePort
const token = spec.token

// Only the bundled danmaku adapter opts into this transport. Other source
// bundles retain their own networking implementation.
globalThis.catNativeDanmakuFetch = (url, options = {}) => new Promise((resolve, reject) => {
  const signal = options.signal
  if (signal?.aborted) { reject(new Error('Danmaku request aborted')); return }
  const body = JSON.stringify({ action: 'danmakuFetch', opt: {
    id: sourceContext.getStore() || startingId || '', url,
    method: options.method || 'GET', headers: options.headers || {},
    body: options.body || '', followRedirects: options.redirect !== 'manual',
  } })
  const req = originalHttpRequest({ host: '127.0.0.1', port: bridgePort,
    path: '/msg', method: 'POST', headers: { [TOKEN_HEADER]: token,
      'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
  }, res => {
    const chunks = []; let size = 0
    res.on('data', chunk => {
      size += chunk.length
      if (size > 12 * 1024 * 1024) { req.destroy(new Error('Danmaku response too large')); return }
      chunks.push(chunk)
    })
    res.on('error', reject)
    res.on('end', () => {
      try {
        const result = JSON.parse(Buffer.concat(chunks).toString('utf8'))
        if (res.statusCode !== 200 || result.error) throw new Error(result.error || 'Native danmaku request failed')
        resolve(result)
      } catch (error) { reject(error) }
    })
  })
  const abort = () => req.destroy(new Error('Danmaku request aborted'))
  signal?.addEventListener('abort', abort, { once: true })
  req.on('close', () => signal?.removeEventListener('abort', abort))
  req.on('error', reject)
  req.setTimeout(45000, () => req.destroy(new Error('Native danmaku request timeout')))
  req.end(body)
})

if (!Number.isInteger(bridgePort) || !token || !spec.sources.length) {
  console.error('[bootstrap] 用法: node bootstrap.js <index.js> <index.config.js> <dataRoot> <bridgePort> <token>')
  console.error('          或: node bootstrap.js <spec.json>')
  process.exit(2)
}

// A Node runtime shares the iOS application's process. Unhandled script failures
// must be reported to the host instead of invoking Node's default process exit.
function reportUnhandled(error) {
  const id = sourceContext.getStore() || startingId || ''
  const message = String(error && error.message || error)
    .replace(/(https?:\/\/)[^/@\s]+@/g, '$1<redacted>@').slice(0, 400)
  console.error(`[bootstrap] 源脚本未处理异常 (${id || 'runtime'}): ${message}`)
  send(id ? 'sourceError' : 'nodeError', { id, message })
}
process.on('uncaughtException', reportUnhandled)
process.on('unhandledRejection', reportUnhandled)
// Source bundles run inside the application's process, not a disposable CLI.
process.exit = (code) => { throw new Error(`源脚本请求退出运行时 (${code || 0})`) }
process.abort = () => { throw new Error('源脚本请求中止运行时') }

// ---- 0. 编译缓存（iOS 无 JIT 环境下最值钱的一笔优化）
// 把"每次启动都要解析几 MB JS"变成"只有第一次解析"。
// iOS 宿主会**提前**用环境变量设好 NODE_COMPILE_CACHE + NODE_COMPILE_CACHE_PORTABLE=1
// （环境变量必须早于 Node 启动才生效），这里就不重复启用；桌面跑时由本行自己开。
if (!process.env.NODE_COMPILE_CACHE) {
  try {
    require('node:module').enableCompileCache?.(path.join(spec.sources[0].dataRoot, '.compile-cache'))
  } catch {
    /* 忽略 */
  }
}

// ---- 1. 环境（逐源在 startSource 里再设一遍 HOME / cwd）
process.env.CATVOD_DISABLE_AUTOSTART = '1' // 告诉 bundle：别自己 listen，用宿主给的 factory
process.env.HOST = '127.0.0.1'
process.env.PORT = '0'
process.env.DEV_HTTP_PORT = '0'

// ---- 3. http.request 补丁：只有发往宿主 /msg 桥的请求才带 token
const originalHttpRequest = http.request

function isBridgeRequest(input, options = {}) {
  let host, port, requestPath
  let method = options.method
  if (typeof input === 'string' || input instanceof URL) {
    const target = new URL(input)
    host = target.hostname
    port = target.port || (target.protocol === 'https:' ? '443' : '80')
    requestPath = target.pathname
  } else if (input && typeof input === 'object') {
    host = input.hostname || input.host
    port = input.port
    requestPath = input.path || input.pathname
    method = input.method
  }
  return (
    String(method || 'GET').toUpperCase() === 'POST' &&
    (host === '127.0.0.1' || host === 'localhost') &&
    Number(port) === bridgePort &&
    String(requestPath || '').split('?', 1)[0] === '/msg'
  )
}

http.request = function authenticatedBridgeRequest(...args) {
  const input = args[0]
  const options = args[1] && typeof args[1] === 'object' ? args[1] : {}
  if (!isBridgeRequest(input, options)) return originalHttpRequest.apply(this, args)
  if (typeof input === 'string' || input instanceof URL) {
    const secured = { ...options, headers: { ...(options.headers || {}), [TOKEN_HEADER]: token, 'X-Lume-Cat-Source': sourceContext.getStore() || startingId || '' } }
    if (args[1] && typeof args[1] === 'object') args[1] = secured
    else args.splice(1, 0, secured)
  } else {
    args[0] = { ...input, headers: { ...(input.headers || {}), [TOKEN_HEADER]: token, 'X-Lume-Cat-Source': sourceContext.getStore() || startingId || '' } }
  }
  return originalHttpRequest.apply(this, args)
}

// ---- 4. 向宿主回报
function send(action, opt = {}) {
  const body = JSON.stringify({ action, opt })
  const request = http.request({
    host: '127.0.0.1',
    port: bridgePort,
    path: '/msg',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body),
      [TOKEN_HEADER]: token,
    },
    timeout: 3000,
  })
  request.on('error', () => {})
  request.on('timeout', () => request.destroy())
  request.end(body)
}

// ------------------------------------------------------------------ 源表
/** id → { id, index, config, dataRoot, server, handler, address, watchdog, startedAt } */
const entries = new Map()
/** 正在 start 哪个 bundle：bundle 在 start 期间调 catServerFactory，用这个认领 */
let startingId = null
let transientSeq = 0

function entryOf(id) {
  if (!entries.has(id)) {
    entries.set(id, { id, server: null, handler: null, address: null, watchdog: null, startedAt: null })
  }
  return entries.get(id)
}

function reportStarted(entry) {
  const address = entry.server && entry.server.address()
  if (!address || typeof address !== 'object' || !address.port) return
  entry.address = `http://127.0.0.1:${address.port}`
  const payload = {
    id: entry.id,
    address: entry.address,
    token,
    pid: process.pid,
    version: process.version,
    arch: process.arch,
  }
  send('sourceStarted', payload)
  // 老的单源回报照旧发（桌面工具与自检屏还在用它）
  send('serverStarted', payload)
  console.log(`[bootstrap] 源已就绪 ${entry.id} → ${entry.address}`)
  startListenerWatchdog(entry)
}

// ---- 2. 注入宿主能力（工厂按"当前正在启动的源"认领 server）
globalThis.catDartServerPort = () => bridgePort

globalThis.catServerFactory = (handler) => {
  const id = startingId || `extra-${++transientSeq}`
  const entry = entryOf(id)
  if (entry.server) {
    console.warn(`[bootstrap] 源 ${id} 又建了一个 server（上一个已存在，保留两个）`)
  }
  const invoke = (req, res) => sourceContext.run(id, () => {
    const failed = (error) => {
      const reason = String(error && error.message || error || 'unknown')
        .replace(/(https?:\/\/)[^/@\s]+@/g, '$1<redacted>@').slice(0, 300)
      console.warn(`[bootstrap] 源请求失败 (${id}): ${reason}`)
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ error: '源请求失败，请检查网盘登录或更换站点' }))
      } else if (!res.writableEnded) res.end()
    }
    try { Promise.resolve(handler(req, res)).catch(failed) } catch (error) { failed(error) }
  })
  const server = http.createServer(invoke)
  const listen = server.listen.bind(server)
  // 强制只监听回环 + 随机端口：避免冲突，也避免把本地服务暴露到局域网
  server.listen = (...args) => {
    const callback = typeof args[args.length - 1] === 'function' ? args[args.length - 1] : undefined
    return listen({ host: '127.0.0.1', port: 0, exclusive: true }, callback)
  }
  entry.handler = invoke
  entry.server = server
  entry.startedAt = entry.startedAt || Date.now()
  server.once('listening', () => reportStarted(entry))
  return server
}

// ---- 7. 本地服务自愈（逐源）
// iOS 会在 App 被挂起时回收它的监听 socket：Node 还活着，但端口连不上了
// （真机实测：启动 85 秒后宿主请求报"无法连接服务器"，而 node_start 并没有返回）。
// 对策：每 10 秒从 Node 侧连一次自己；连不上就用**同一个端口**重建一个 server
// （换端口会让宿主手里的旧地址失效，所以必须原地重绑）。
function startListenerWatchdog(entry) {
  if (entry.watchdog || !entry.server) return
  const address = entry.server.address()
  if (!address || typeof address !== 'object' || !address.port) return
  const port = address.port

  entry.watchdog = setInterval(() => {
    if (entry.rebindingNow) return
    const probe = net.connect({ host: '127.0.0.1', port })
    let settled = false
    const finish = (alive) => {
      if (settled) return
      settled = true
      probe.removeAllListeners()
      probe.destroy()
      if (!alive) rebind(entry, port)
    }
    probe.setTimeout(2000)
    probe.once('connect', () => finish(true))
    probe.once('error', () => finish(false))
    probe.once('timeout', () => finish(false))
  }, 10000)
  entry.watchdog.unref?.()
  console.log(`[bootstrap] 源 ${entry.id} 监听自愈已开启（每 10s 自检 127.0.0.1:${port}）`)
}

function rebind(entry, port) {
  if (entry.rebindingNow || !entry.handler) return
  entry.rebindingNow = true
  console.warn(`[bootstrap] 源 ${entry.id} 的监听已失效（App 挂起后 socket 被回收）→ 原地重绑 127.0.0.1:${port}`)

  const fresh = http.createServer(entry.handler)
  fresh.once('error', (error) => {
    console.warn(`[bootstrap] 源 ${entry.id} 重绑失败：${error && error.code ? error.code : error}`)
    entry.rebindingNow = false
  })
  try {
    fresh.listen({ host: '127.0.0.1', port, exclusive: true }, () => {
      entry.server = fresh
      console.warn(`[bootstrap] 源 ${entry.id} 已重新监听 http://127.0.0.1:${port}`)
      reportStarted(entry)
      entry.rebindingNow = false
    })
  } catch (error) {
    console.warn(`[bootstrap] 源 ${entry.id} 重绑异常：${error && error.message}`)
    entry.rebindingNow = false
  }
}

// ---- 5. 加载 bundle
/** 优先 CJS require；遇到 ESM 语法则退回动态 import（esbuild 产物两种形态都有） */
async function loadModule(file) {
  const absolute = path.resolve(file)
  try {
    return require(absolute)
  } catch (error) {
    const message = String((error && error.message) || error)
    if (/Cannot use import statement|Unexpected token 'export'|require\(\) of ES Module|ERR_REQUIRE_ESM|ERR_USE_ESM/i.test(message)) {
      return await import(pathToFileURL(absolute).href)
    }
    throw error
  }
}

/** 等某个源真的 listen 上（最多 timeoutMs） */
function waitForListen(entry, timeoutMs = 60000) {
  if (entry.address) return Promise.resolve(entry.address)
  return new Promise((resolve) => {
    const started = Date.now()
    const timer = setInterval(() => {
      if (entry.address || Date.now() - started > timeoutMs) {
        clearInterval(timer)
        resolve(entry.address)
      }
    }, 100)
    timer.unref?.()
  })
}

/** 启动一个源：设环境 → chdir → require → start()。失败只影响它自己 */
async function startSource(source) {
  const entry = entryOf(source.id)
  if (entry.entryStarted && entry.server) {
    console.warn(`[bootstrap] 源 ${source.id} 已经在跑，忽略重复启动`)
    return entry.address
  }
  entry.entryStarted = true
  lastSourceErrors.delete(source.id)
  entry.index = source.index
  entry.config = source.config
  entry.dataRoot = source.dataRoot
  entry.startedAt = Date.now()

  // 环境是进程级的，所以每个源在**自己 start 之前**把 HOME/cwd 摆成自己的
  // （bundle 在 start 期间读 cwd/HOME 来决定它的数据目录，那之后就绑定了）
  process.env.HOME = source.dataRoot
  try {
    process.chdir(source.dataRoot)
  } catch (error) {
    console.warn(`[bootstrap] 源 ${source.id} chdir 失败：${error && error.message}`)
  }

  const isolated = isolateIfLoaded(source)
  startingId = source.id
  try {
    const configModule = await loadModule(isolated.config)
    const indexModule = await loadModule(isolated.index)
    loadedPaths.add(source.index)
    loadedPaths.add(isolated.index)
    const config = (configModule && (configModule.default || configModule)) || {}
    const runtime = indexModule && (indexModule.default || indexModule)
    if (!runtime || typeof runtime.start !== 'function') {
      throw new Error('Node bundle does not export start()')
    }
    console.log(`[bootstrap] 启动源 ${source.id}（${path.basename(path.dirname(source.index))}）`)
    await sourceContext.run(source.id, () => runtime.start(config))
    const address = await waitForListen(entry, 60000)
    if (!address) {
      const message = 'start() 返回了，但始终没有监听任何端口（多数是这份 bundle 已经在这个进程里跑过）'
      lastSourceErrors.set(source.id, message)
      send('sourceError', { id: source.id, message })
      return null
    }
    return address
  } catch (error) {
    const message = String((error && (error.message || error.stack)) || error)
    entry.entryStarted = false
    console.error(`[bootstrap] 源 ${source.id} 启动失败：${message}`)
    lastSourceErrors.set(source.id, message.slice(0, 300))
    send('sourceError', { id: source.id, message: message.slice(0, 600) })
    return null
  } finally {
    startingId = null
  }
}

/** 在这个进程里 require 过的 index.js 路径 */
const loadedPaths = new Set()

/** 每个源最后一次启动失败的原因（控制口把它带回给宿主） */
const lastSourceErrors = new Map()

/**
 * 同一个 index.js 只能 require 一次（Node 有模块缓存）：第二次 require 拿到的是**同一个
 * 模块实例**，而 bundle 的 start() 大多带"只跑一次"的保护 → 第二个源根本起不来。
 * 所以在"这份文件已经加载过"时，先把它复制进新源自己的数据目录，用新路径加载，
 * 这样两个源才是真正互相独立的实例（镜像源、运行期追加源都靠这条）。
 */
function isolateIfLoaded(source) {
  if (!loadedPaths.has(source.index)) return source
  try {
    const suffix = `${Date.now()}-${++transientSeq}`
    const copyIndex = path.join(source.dataRoot, `.lumebox-${suffix}.index.js`)
    const copyConfig = path.join(source.dataRoot, `.lumebox-${suffix}.index.config.js`)
    fs.copyFileSync(source.index, copyIndex)
    fs.copyFileSync(source.config, copyConfig)
    console.log(`[bootstrap] 源 ${source.id} 与已加载的 bundle 是同一份文件 → 复制后再加载（保证两份实例互不干扰）`)
    return { ...source, index: copyIndex, config: copyConfig }
  } catch (error) {
    console.warn(`[bootstrap] 源 ${source.id} 复制 bundle 失败：${error && error.message}（仍按原路径加载）`)
    return source
  }
}

// ------------------------------------------------------------------ 控制口
// 这是**我们自己的** HTTP 服务（只有下面这几个 handler），
// 让宿主在 Node 跑起来之后还能追加/停掉一个源 —— 换源不用重启 App。
let controlServer = null
let controlPort = 0

function readJsonBody(req) {
  return new Promise((resolve) => {
    let raw = ''
    req.on('data', (chunk) => {
      raw += chunk
      if (raw.length > 1 << 20) req.destroy()
    })
    req.on('end', () => {
      try {
        resolve(raw ? JSON.parse(raw) : {})
      } catch {
        resolve({})
      }
    })
    req.on('error', () => resolve({}))
  })
}

function json(res, status, payload) {
  const body = JSON.stringify(payload)
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(body) })
  res.end(body)
}

function controlStatus() {
  const sources = []
  for (const entry of entries.values()) {
    let listening = false
    try {
      const address = entry.server && entry.server.address()
      listening = Boolean(address && typeof address === 'object' && address.port)
    } catch {
      listening = false
    }
    sources.push({
      id: entry.id,
      address: listening ? entry.address : null,
      listening,
      startedAt: entry.startedAt || null,
    })
  }
  return { ok: true, pid: process.pid, node: process.version, sources }
}

function startControlServer() {
  controlServer = http.createServer(controlHandler)

  controlServer.once('error', (error) => {
    console.warn(`[bootstrap] 控制口启动失败：${error && error.message}`)
  })
  controlServer.listen({ host: '127.0.0.1', port: 0, exclusive: true }, () => {
    controlPort = controlServer.address().port
    console.log(`[bootstrap] 控制口已监听 http://127.0.0.1:${controlPort}`)
    send('controlReady', { address: `http://127.0.0.1:${controlPort}`, pid: process.pid, version: process.version })
  })

  // 控制口也会被 iOS 挂起回收 → 同样自愈（同端口原地重绑）
  setInterval(() => {
    if (!controlPort) return
    const probe = net.connect({ host: '127.0.0.1', port: controlPort })
    let settled = false
    const finish = (alive) => {
      if (settled) return
      settled = true
      probe.removeAllListeners()
      probe.destroy()
      if (alive) return
      const fresh = http.createServer(controlHandler)
      fresh.listen({ host: '127.0.0.1', port: controlPort, exclusive: true }, () => {
        controlServer = fresh
        console.warn(`[bootstrap] 控制口已重新监听 127.0.0.1:${controlPort}`)
        send('controlReady', { address: `http://127.0.0.1:${controlPort}`, pid: process.pid, version: process.version })
      })
    }
    probe.setTimeout(2000)
    probe.once('connect', () => finish(true))
    probe.once('error', () => finish(false))
    probe.once('timeout', () => finish(false))
  }, 10000).unref?.()
}

async function controlHandler(req, res) {
  if (req.headers['x-catvod-token'] !== token) return json(res, 403, { ok: false, error: 'bad token' })
  const pathname = String(req.url || '').split('?', 1)[0]

  if (req.method === 'GET' && pathname === '/ctl/status') {
    return json(res, 200, controlStatus())
  }

  if (req.method === 'POST' && pathname === '/ctl/source') {
    const body = await readJsonBody(req)
    if (!body.index || !body.config || !body.dataRoot) {
      return json(res, 400, { ok: false, error: 'need index/config/dataRoot' })
    }
    const source = {
      id: String(body.id || `extra-${++transientSeq}`),
      index: path.resolve(String(body.index)),
      config: path.resolve(String(body.config)),
      dataRoot: path.resolve(String(body.dataRoot)),
    }
    console.log(`[bootstrap] 控制口：追加源 ${source.id}`)
    const address = await startSource(source)
    return json(res, address ? 200 : 500, { ok: Boolean(address), id: source.id, address })
  }

  if (req.method === 'POST' && pathname === '/ctl/stop') {
    const body = await readJsonBody(req)
    const entry = entries.get(String(body.id || ''))
    if (!entry || !entry.server) return json(res, 404, { ok: false, error: 'no such source' })
    const id = entry.id
    await new Promise((resolve) => {
      try {
        entry.server.close(() => resolve())
      } catch {
        resolve()
      }
      setTimeout(resolve, 1500)
    })
    entry.server = null
    entry.address = null
    // ⚠️ 必须复位：否则用户"关掉再打开"这个源时会被"已经在跑"挡住 → 控制口返回 500
    //（真机上踩过：源管理里关掉再打开 9280，报 `/ctl/source 返回 500 {"address":null}`）
    entry.entryStarted = false
    if (entry.watchdog) {
      clearInterval(entry.watchdog)
      entry.watchdog = null
    }
    console.log(`[bootstrap] 控制口：已停用源 ${id}（代码与定时器要等 App 重启才彻底释放）`)
    return json(res, 200, { ok: true, id })
  }

  return json(res, 404, { ok: false, error: 'not found' })
}

// ------------------------------------------------------------------ 主流程
async function main() {
  startControlServer()
  // 逐个起：串行最稳（同时起多个 bundle 会让 cwd/HOME 互相打架）
  for (const source of spec.sources) {
    const address = await startSource(source)
    if (!address) {
      // 老调用方（单源）期望失败时退出并报 nodeError，保持一致
      if (spec.sources.length === 1) {
        send('nodeError', { message: `源启动失败：${source.id}`, token })
        return
      }
    }
  }
  const ready = [...entries.values()].filter((entry) => entry.address)
  console.log(`[bootstrap] 全部启动完成：${ready.length}/${spec.sources.length} 个源在跑`)
  if (!ready.length) {
    send('nodeError', { message: '所有源都没能启动（看上面的 [bootstrap] 日志）', token })
  }
}

main().catch((error) => {
  // ---- 6. 失败上报
  send('nodeError', { message: String((error && (error.stack || error.message)) || error), token })
})
