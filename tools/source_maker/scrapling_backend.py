"""Scrapling 0.5 fetchers in a source-scoped worker; no credentials exported."""
import asyncio
import json
import os
from pathlib import Path
import sys

HTTP_ENGINES = {'scrapling-fetcher', 'scrapling-async', 'scrapling-session', 'scrapling-async-session'}
BROWSER_ENGINES = {'scrapling-browser', 'scrapling-async-browser', 'scrapling-browser-session', 'scrapling-async-browser-session'}


def edge_path():
    for root in (os.environ.get('PROGRAMFILES(X86)', ''), os.environ.get('PROGRAMFILES', ''), os.environ.get('LOCALAPPDATA', '')):
        candidate = Path(root) / 'Microsoft/Edge/Application/msedge.exe'
        if candidate.is_file():
            return str(candidate)
    raise ValueError('没有找到 Microsoft Edge，请先安装 Edge')


def run_worker(options, send):
    from core import validate_url, MAX_BYTES, UA
    from browser_session import same_site
    from scrapling.fetchers import Fetcher, AsyncFetcher, FetcherSession
    from scrapling.fetchers import StealthyFetcher, StealthySession, AsyncStealthySession
    engine = options['engine']
    url = validate_url(options['url'])
    runner = asyncio.Runner()
    manager = client = None
    cookie_state = []
    network = []
    from browser_actions import program, network_row
    async_mode = 'async' in engine
    browser_mode = engine in BROWSER_ENGINES
    session_mode = engine.endswith('session')
    defaults = dict(timeout=18, retries=0, impersonate=None, stealthy_headers=False,
                    headers={'User-Agent': UA}, max_redirects=8)
    browser_options = dict(executable_path=edge_path(), headless=bool(options.get('hidden_test')),
        solve_cloudflare=False, google_search=False, timeout=18000, wait=1000,
        retries=1, load_dom=True, disable_resources=False, record_requests=True,
        max_recorded_requests=40) if browser_mode else {}

    def setup(page):
        def record(value):
            try:
                if value.request.resource_type in ('fetch', 'xhr') and same_site(url, value.url):
                    raw = value.body()
                    if len(raw) <= 256 * 1024:
                        network.append(network_row(value.url, value.status, json.loads(raw)))
                        del network[:-20]
            except Exception:
                pass
        page.on('response', record)

    async def async_setup(page):
        async def record(value):
            try:
                if value.request.resource_type in ('fetch', 'xhr') and same_site(url, value.url):
                    raw = await value.body()
                    if len(raw) <= 256 * 1024:
                        network.append(network_row(value.url, value.status, json.loads(raw)))
                        del network[:-20]
            except Exception:
                pass
        page.on('response', record)
    if browser_mode:
        browser_options['page_setup'] = async_setup if async_mode else setup

    def resolve(value):
        if async_mode:
            async def wait():
                return await value
            return runner.run(wait())
        return value

    def response(value):
        if not same_site(url, value.url):
            raise ValueError('页面跳转到其他站点；请使用新网址重新开始')
        if not 200 <= value.status < 300:
            raise ValueError('站点返回 HTTP ' + str(value.status))
        raw = value.body
        if len(raw) > MAX_BYTES:
            raise ValueError('页面超过 6MB')
        body = raw.decode(value.encoding or 'utf-8', errors='replace') if isinstance(raw, bytes) else str(raw)
        if 'cf-chl-' in body or '<title>Just a moment' in body:
            raise ValueError('页面需要验证，请使用浏览器会话手动完成后继续')
        return {'ok': True, 'url': value.url, 'html': body}

    def manual(page):
        nonlocal cookie_state
        while True:
            if options.get('hidden_test'):
                action = 'accept'
            else:
                line = sys.stdin.readline()
                if not line:
                    raise ValueError('会话已取消')
                action = json.loads(line)['action']
            if action == 'close':
                raise ValueError('网页验证已取消')
            if action != 'accept':
                continue
            info = page.evaluate('({url:location.href,title:document.title,ready:document.readyState,html:document.documentElement.outerHTML})')
            if not same_site(url, info['url']) or info['ready'] != 'complete' or 'cf-chl-' in info['html']:
                send({'event': 'notice', 'message': '请在原站点手动完成验证，等待页面加载完成后继续'})
                if options.get('hidden_test'):
                    raise ValueError('本地浏览器测试页面未就绪')
                continue
            cookie_state = page.context.cookies()
            return

    async def async_manual(page):
        nonlocal cookie_state
        while True:
            if options.get('hidden_test'):
                action = 'accept'
            else:
                line = await asyncio.to_thread(sys.stdin.readline)
                if not line:
                    raise ValueError('会话已取消')
                action = json.loads(line)['action']
            if action == 'close':
                raise ValueError('网页验证已取消')
            if action != 'accept':
                continue
            info = await page.evaluate('({url:location.href,ready:document.readyState,html:document.documentElement.outerHTML})')
            if not same_site(url, info['url']) or info['ready'] != 'complete' or 'cf-chl-' in info['html']:
                send({'event': 'notice', 'message': '请手动完成验证后继续'})
                if options.get('hidden_test'):
                    raise ValueError('本地浏览器测试页面未就绪')
                continue
            cookie_state = await page.context.cookies()
            return

    try:
        if browser_mode:
            if session_mode:
                manager = (AsyncStealthySession if async_mode else StealthySession)(**browser_options)
                resolve(manager.start())
                client = manager
                first = resolve(client.fetch(url, page_action=async_manual if async_mode else manual))
            elif async_mode:
                first = runner.run(StealthyFetcher.async_fetch(url, **browser_options, page_action=async_manual))
            else:
                first = StealthyFetcher.fetch(url, **browser_options, page_action=manual)
            initial = response(first)
        elif session_mode:
            manager = FetcherSession(**defaults)
            client = resolve(manager.__aenter__()) if async_mode else manager.__enter__()
        send({'ok': True, 'url': url, 'user_agent': UA, 'cookie_count': len(cookie_state)})
        cached = initial if browser_mode else None
        for line in sys.stdin:
            request = json.loads(line)
            if request['action'] == 'close':
                break
            if request['action'] == 'accept':
                continue
            if request['action'] == 'network':
                send({'ok': True, 'network': network})
                continue
            if request['action'] == 'snapshot':
                send({'ok': False, 'error': 'Scrapling 不保留可手动导航的当前标签页，请选择推荐浏览器、Playwright、Selenium 或内置浏览器'})
                continue
            try:
                target = validate_url(request['url'])
                if not same_site(url, target):
                    raise ValueError('当前会话仅用于当前站点')
                if cached and target == url and not request.get('selector') and not request.get('actions') and not request.get('purpose'):
                    send(cached)
                    cached = None
                    continue
                cached = None
                if browser_mode:
                    extra = {'wait_selector': request['selector']} if request.get('selector') else {}
                    if request.get('actions') or request.get('purpose'):
                        extra = {}
                        if async_mode:
                            async def action(page):
                                await page.evaluate(program(request.get('actions'), request.get('selector', ''), request.get('purpose', '')))
                        else:
                            def action(page):
                                page.evaluate(program(request.get('actions'), request.get('selector', ''), request.get('purpose', '')))
                        extra['page_action'] = action
                    if session_mode:
                        value = resolve(client.fetch(target, **extra))
                    elif async_mode:
                        value = runner.run(StealthyFetcher.async_fetch(target, **browser_options, cookies=cookie_state, **extra))
                    else:
                        value = StealthyFetcher.fetch(target, **browser_options, cookies=cookie_state, **extra)
                elif session_mode:
                    value = resolve(client.get(target))
                elif async_mode:
                    value = runner.run(AsyncFetcher.get(target, **defaults))
                else:
                    value = Fetcher.get(target, **defaults)
                send(response(value))
            except Exception as error:
                send({'ok': False, 'error': str(error)})
    except Exception as error:
        send({'ok': False, 'error': 'Scrapling：' + str(error)})
    finally:
        if manager:
            try:
                if browser_mode:
                    resolve(manager.close())
                elif async_mode:
                    runner.run(manager.__aexit__(None, None, None))
                else:
                    manager.__exit__(None, None, None)
            except Exception:
                pass
        runner.close()
