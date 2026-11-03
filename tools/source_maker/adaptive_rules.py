"""Persist only validated selector samples and relocate changed structures."""
from collections import OrderedDict
import hashlib
import json
import os
from pathlib import Path
import re
from urllib.parse import urlsplit


class AdaptiveFetcher:
    supports_selector = True
    def __init__(self, base, store):
        self.base = base
        self.adaptive_store = store
        self.pages = OrderedDict()
    @property
    def browser_mode(self):
        return getattr(self.base, 'browser_mode', False)

    def request(self, options):
        method = getattr(self.base, 'request', None)
        if method is None:
            raise ValueError('该接口需要 HTTP 请求模式，请使用“开始制作”重新检查')
        return method(options)

    def get(self, url, selector='', purpose='', cancel_event=None):
        from core import Fetcher
        result = self.base.get(url, selector=selector, purpose=purpose) if self.browser_mode else self.base.get(url, selector=selector) if hasattr(self.base, 'accept') else self.base.get(url, cancel_event=cancel_event) if isinstance(self.base, Fetcher) else self.base.get(url)
        self.pages[result[0]] = result[1]
        while len(self.pages) > 10:
            self.pages.popitem(last=False)
        return result


class AdaptiveProfiles:
    def __init__(self, root=None):
        self.root = Path(root) if root else Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'LumeBox/SourceMaker/adaptive'
        self.root.mkdir(parents=True, exist_ok=True)
        self.stores = {}

    def files(self, url):
        p = urlsplit(url)
        key = hashlib.sha256((p.scheme + '://' + p.netloc + p.path).encode()).hexdigest()
        return self.root / (key + '.json'), self.root / (key + '.sqlite')

    def selector(self, html, url):
        from scrapling import Selector
        from scrapling.core.storage import SQLiteStorageSystem
        class ProfileStorage(SQLiteStorageSystem.__wrapped__):
            def _get_base_url(self, default_value='default'):
                return urlsplit(self.url or '').hostname or default_value
            def close(self):
                if getattr(self, '_profile_closed', False) or not hasattr(self, 'connection'):
                    return
                self._profile_closed = True
                super().close()
        _, database = self.files(url)
        key = str(database)
        if key not in self.stores:
            self.stores[key] = ProfileStorage(storage_file=key, url=url)
        return Selector(html, url=url, adaptive=True, _storage=self.stores[key])

    def recover(self, html, url, key):
        path, _ = self.files(url)
        if not path.exists():
            return '', []
        profile = json.loads(path.read_text(encoding='utf-8'))
        old = profile.get(key, '')
        if not old:
            return '', []
        page = self.selector(html, url)
        nodes = page.css(old)
        if nodes:
            return old, nodes
        nodes = page.css(old, identifier=key, adaptive=True, percentage=75)
        if not nodes:
            return '', []
        # Turn the relocated element into ordinary CSS the mobile runtime can use.
        node = nodes[0]
        classes = [v for v in node.attrib.get('class', '').split() if re.fullmatch(r'[A-Za-z_][\w-]*', v)]
        if classes:
            selector = node.tag + ''.join('.' + v for v in classes[:3])
        elif re.fullmatch(r'[A-Za-z_][\w-]*', node.attrib.get('id', '')):
            selector = '#' + node.attrib['id']
        else:
            selector = node.generate_css_selector
            if ':' in selector:
                return '', []
        return selector, page.css(selector)

    def learn(self, config, rows, fetcher):
        if config.get('mode') != 'html':
            return 0
        profile = {}
        list_url = config['list'].replace('{page}', '1')
        detail_url = rows[0]['id'] if rows else ''
        pages = fetcher.pages
        pairs = [('listSelector', list_url), ('chapterSelector', detail_url)]
        if config.get('imageSelector'):
            from bs4 import BeautifulSoup
            from urllib.parse import urljoin
            body = pages.get(detail_url, '')
            first = BeautifulSoup(body, 'html.parser').select_one(config.get('chapterSelector') or 'a[href*="/chapter/"]')
            if first and first.get('href'):
                pairs.append(('imageSelector', urljoin(detail_url, first['href'])))
        for key, address in pairs:
            selector = config.get(key)
            if not selector or not address:
                continue
            html = pages.get(address)
            if html is None:
                _, html = fetcher.get(address)
            page = self.selector(html, config['url'])
            nodes = page.css(selector)
            if nodes:
                page.save(nodes[0]._root, key)
                profile[key] = selector
        if profile:
            path, _ = self.files(config['url'])
            temp = path.with_suffix('.tmp')
            temp.write_text(json.dumps(profile, ensure_ascii=False), encoding='utf-8')
            temp.replace(path)
        return len(profile)

    def forget(self, url):
        path, database = self.files(url)
        # Remove the lookup; open SQLite handles need not be deleted on Windows.
        if path.exists():
            path.unlink()
        store = self.stores.pop(str(database), None)
        if store:
            store.close()
        for file in (database, Path(str(database) + '-wal'), Path(str(database) + '-shm')):
            if file.exists():
                file.unlink()

    def close(self):
        for store in self.stores.values():
            store.close()
        self.stores.clear()
