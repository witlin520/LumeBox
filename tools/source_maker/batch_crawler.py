"""Scrapy public-page collection + the same conversion and validation pipeline."""
import json
import subprocess
import sys
import hashlib
import queue
import threading
from pathlib import Path

PREFIX = 'LUME_BATCH:'


def crawl_public_pages(urls, settings=None, stop=None, progress=None):
    cmd = [sys.executable, '--scrapy-worker'] if getattr(sys, 'frozen', False) else [sys.executable, str(Path(__file__).with_name('app.py')), '--scrapy-worker']
    process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, encoding='utf-8', creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0)
    process.stdin.write(json.dumps({'urls': urls, 'settings': settings or {}}))
    process.stdin.close()
    events = queue.Queue()
    def read():
        for line in process.stdout:
            if line.startswith(PREFIX):
                events.put(json.loads(line[len(PREFIX):]))
        events.put(None)
    threading.Thread(target=read, daemon=True).start()
    import time
    deadline = time.monotonic() + max(65, len(urls) * 35)
    try:
        while time.monotonic() < deadline:
            if stop and stop.is_set():
                raise InterruptedError('批量任务已暂停，可使用相同目录继续')
            try:
                value = events.get(timeout=.2)
            except queue.Empty:
                continue
            if value is None:
                break
            if value.get('event') == 'progress':
                if progress:
                    progress('Scrapy 已处理：' + value['url'])
            elif value.get('error'):
                raise ValueError(value['error'])
            elif 'pages' in value:
                return value['pages']
        raise ValueError('Scrapy 未返回完整结果，请检查网络或稍后重试')
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=5)
        process.stdout.close()


def run_scrapy_worker():
    def finish(value):
        print(PREFIX + json.dumps(value, ensure_ascii=True), flush=True)
    try:
        options = json.loads(sys.stdin.read())
        import scrapy
        from scrapy.crawler import CrawlerProcess
        from core import validate_url, UA, MAX_BYTES
        urls = list(dict.fromkeys(validate_url(u) for u in options['urls']))[:10]
        settings = options.get('settings') or {}
        pages = {}
        class CatalogueSpider(scrapy.Spider):
            name = 'lume_public_catalogues'
            async def start(self):
                for url in urls:
                    yield scrapy.Request(url, callback=self.received, errback=self.failed,
                                         meta={'original': url}, dont_filter=True)
            def received(self, response):
                original = response.meta['original']
                if len(response.body) > MAX_BYTES:
                    pages[original] = {'error': '页面超过 6MB'}
                else:
                    pages[original] = {'url': response.url, 'html': response.text}
                finish({'event': 'progress', 'url': original})
            def failed(self, failure):
                pages[failure.request.meta['original']] = {'error': str(failure.value)}
                finish({'event': 'progress', 'url': failure.request.meta['original']})
        process = CrawlerProcess(settings={'LOG_ENABLED': False, 'ROBOTSTXT_OBEY': True,
            'COOKIES_ENABLED': False, 'USER_AGENT': UA, 'CONCURRENT_REQUESTS': max(1, min(4, int(settings.get('concurrency', 2)))),
            'DOWNLOAD_DELAY': max(.3, min(5, float(settings.get('delay', .5)))),
            'AUTOTHROTTLE_ENABLED': True, 'AUTOTHROTTLE_START_DELAY': .5, 'AUTOTHROTTLE_MAX_DELAY': 5,
            'DOWNLOAD_TIMEOUT': 18, 'DOWNLOAD_MAXSIZE': MAX_BYTES,
            'RETRY_TIMES': max(0, min(2, int(settings.get('retries', 1)))), 'TELNETCONSOLE_ENABLED': False})
        process.crawl(CatalogueSpider)
        process.start()
        for url in urls:
            pages.setdefault(url, {'error': '未采集，可能被 robots 规则或请求失败阻止'})
        finish({'pages': pages})
    except Exception as e:
        finish({'error': str(e)})


def batch_convert(urls, target, directory, settings=None, stop=None, progress=None):
    from core import Fetcher, discover, source_filename
    from exports import export_source
    from verifier import verify_with_fallback
    output = Path(directory)
    output.mkdir(parents=True, exist_ok=True)
    checkpoint = output / '制源任务.json'
    # Old checkpoints may contain automatically converted PY output. Never
    # silently reuse that result for a JS batch under the confirmation policy.
    identity = {'urls': urls, 'target': target, 'formatPolicy': 'explicit-python-v1'}
    previous = {}
    if checkpoint.exists():
        saved = json.loads(checkpoint.read_text(encoding='utf-8'))
        if saved.get('identity') == identity:
            for item in saved.get('reports', []):
                filename = item.get('file', '')
                if item.get('ok') and filename and Path(filename).name == filename:
                    file = output / filename
                    if file.is_file() and hashlib.sha256(file.read_bytes()).hexdigest() == item.get('sha256'):
                        previous[item['url']] = item
    pending = [url for url in urls if url not in previous]
    reports = list(previous.values())
    def save():
        temp = checkpoint.with_suffix('.tmp')
        temp.write_text(json.dumps({'identity': identity, 'reports': reports}, ensure_ascii=False, indent=2), encoding='utf-8')
        temp.replace(checkpoint)
        (output / '采集诊断.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')
    save()
    try:
        pages = crawl_public_pages(pending, settings, stop, progress) if pending else {}
    except InterruptedError:
        return reports
    class CachedFetcher(Fetcher):
        def get(self, url):
            if stop and stop.is_set():
                raise InterruptedError('批量任务已暂停')
            if url in pages:
                value = pages[url]
                if value.get('error'):
                    raise ValueError(value['error'])
                return value['url'], value['html']
            return super().get(url)
    for index, url in enumerate(pending):
        if stop and stop.is_set():
            break
        if progress:
            progress(f'正在识别与验证 {index + 1}/{len(pending)}：{url}')
        try:
            fetcher = CachedFetcher()
            config, rows, message = discover(url, target, fetcher)
            checked, result = verify_with_fallback(config, rows, fetcher)
            if stop and stop.is_set():
                break
            extension, raw, route = export_source(checked, rows)
            filename = source_filename(checked, extension)
            if (output / filename).exists():
                filename = source_filename(checked, '') + '-' + checked['id'][-8:] + extension
            (output / filename).write_bytes(raw)
            reports.append({'url': url, 'ok': True, 'file': filename, 'sha256': hashlib.sha256(raw).hexdigest(), 'result': result, 'import': route})
        except Exception as e:
            reports.append({'url': url, 'ok': False, 'error': str(e)})
        save()
    return reports
