"""A standalone Spider for LumeBox's assets/python/lume_python.py adapter."""
import json
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.parse import urljoin, quote, unquote
import re
from bs4 import BeautifulSoup


class Spider:
    def __init__(self):
        self.known = {}
        self.pages = {}

    def init(self, extend=''):
        pass

    def _get(self, url):
        with urlopen(Request(url, headers={'Referer': CONFIG['url']}), timeout=15) as r:
            raw = r.read(6 * 1024 * 1024 + 1)
            if len(raw) > 6 * 1024 * 1024:
                raise ValueError('网页超过 6MB')
            return raw.decode(r.headers.get_content_charset() or 'utf-8', errors='replace')

    def _items(self, html, base):
        soup = BeautifulSoup(html, 'html.parser')
        cards = soup.select(CONFIG.get('listSelector') or 'a[href]')
        out, seen = [], set()
        for card in cards:
            link = card if card.name == 'a' and card.get('href') else card.select_one(CONFIG.get('linkSelector') or 'a[href]')
            if not link:
                continue
            address = urljoin(base, link['href'])
            if not address.startswith(('http://', 'https://')) or address in seen:
                continue
            if not CONFIG.get('listSelector') and CONFIG.get('links') and not re.search(CONFIG['links'], address, re.I):
                continue
            heading = card.select_one(CONFIG.get('titleSelector') or 'h2,h3,h4,.title')
            image = card.select_one(CONFIG.get('coverSelector') or 'img,source')
            title = (heading.get_text(' ', strip=True) if heading else '') or link.get('title') or (image.get('alt') if image else '') or link.get_text(' ', strip=True)
            if not title:
                continue
            cover = ''
            if image:
                for key in ['data-original', 'data-lazy-src', 'data-src', 'src']:
                    candidate = image.get(key) or ''
                    if candidate and not candidate.startswith('data:'):
                        cover = urljoin(base, candidate)
                        break
            row = {'vod_id': address, 'vod_name': title, 'vod_pic': cover}
            out.append(row)
            seen.add(address)
            self.known[address] = row
            if len(self.known) > 150:
                self.known.pop(next(iter(self.known)))
        return out

    def _listing(self, page=1, tid='', keyword='', filters=None):
        page = int(page)
        address = CONFIG['search'] if keyword else tid or CONFIG['list']
        if keyword and not address:
            raise ValueError('尚未配置搜索网址')
        key = json.dumps([address, keyword, filters or {}], sort_keys=True)
        if page > 1 and '{page}' not in address and (key, page) not in self.pages:
            return {'list': [], 'page': page, 'pagecount': page}
        url = address.replace('{page}', str(page)).replace('{keyword}', quote(keyword))
        if filters:
            from urllib.parse import urlsplit, urlunsplit, parse_qsl
            invalid = set(filters) - set(CONFIG.get('filterKeys', []))
            if invalid:
                raise ValueError('未适配的筛选项：' + ','.join(invalid))
            if not keyword and not tid:
                url = CONFIG.get('filterAction') or url
            parts = urlsplit(url)
            values = dict(parse_qsl(parts.query)); values.update(filters)
            url = urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(values), parts.fragment))
        url = self.pages.get((key, page), url)
        html = self._get(url)
        rows = self._items(html, url)
        if not rows:
            raise ValueError('列表没有识别到作品')
        soup = BeautifulSoup(html, 'html.parser')
        next_url = ''
        for a in soup.select(CONFIG.get('nextSelector') or 'a[href]'):
            if 'next' in (a.get('rel') or []) or re.match(r'^(下一[页頁]|下[页頁]|next|[›»])$', a.get_text(strip=True), re.I):
                next_url = urljoin(url, a.get('href', ''))
                if next_url != url:
                    break
        if next_url and next_url != url:
            self.pages[key, page + 1] = next_url
        return {'list': rows, 'page': page, 'pagecount': page + 1 if next_url and next_url != url else page}

    def _api(self, **params):
        url = CONFIG['api'] + ('&' if '?' in CONFIG['api'] else '?') + urlencode(params)
        with urlopen(Request(url, headers={'Referer': CONFIG['url']}), timeout=15) as r:
            if r.status < 200 or r.status >= 300:
                raise ValueError('接口 HTTP ' + str(r.status))
            data = r.read(6 * 1024 * 1024 + 1)
            if len(data) > 6 * 1024 * 1024:
                raise ValueError('接口响应过大')
            return json.loads(data)

    def homeContent(self, filter=False):
        if CONFIG['mode'] != 'maccms':
            soup = BeautifulSoup(self._get(CONFIG['url']), 'html.parser')
            categories = [{'type_id': CONFIG['url'], 'type_name': '全部'}]
            for a in soup.select('a[href]'):
                address = urljoin(CONFIG['url'], a['href'])
                if CONFIG.get('categoryLinks') and re.search(CONFIG['categoryLinks'], address, re.I):
                    categories.append({'type_id': address, 'type_name': a.get_text(' ', strip=True)})
            groups = []
            for select in soup.select('form select[name]'):
                key = select.get('name', '')
                if key not in CONFIG.get('filterKeys', []):
                    continue
                values = [{'n': option.get_text(' ', strip=True), 'v': option.get('value', '')} for option in select.select('option')]
                if values:
                    groups.append({'key': key, 'name': select.get('aria-label') or key, 'value': values})
            return {'class': categories, 'filters': {c['type_id']: groups for c in categories} | {'': groups}}
        return self._api(ac='list')

    def homeVideoContent(self):
        if CONFIG['mode'] != 'maccms':
            return self._listing()
        return self._api(ac='detail', pg=1)

    def categoryContent(self, tid, pg, filter=False, extend=None):
        if CONFIG['mode'] != 'maccms':
            return self._listing(pg, '' if tid == CONFIG['url'] else tid, filters=extend)
        return self._api(ac='detail', t=tid, pg=pg)

    def searchContent(self, key, quick=False, pg=1):
        if CONFIG['mode'] != 'maccms':
            return self._listing(pg, keyword=key)
        return self._api(ac='detail', wd=key, pg=pg)

    def detailContent(self, ids):
        if CONFIG['mode'] != 'maccms':
            address = str(ids[0])
            soup = BeautifulSoup(self._get(address), 'html.parser')
            heading = soup.select_one('h1') or soup.title
            row = dict(self.known.get(address, {'vod_id': address}))
            row['vod_name'] = heading.get_text(' ', strip=True) if heading else row.get('vod_name', address)
            links = soup.select(CONFIG['chapterSelector']) if CONFIG.get('chapterSelector') else [a for a in soup.select('a[href]') if re.search(CONFIG['chapters'], urljoin(address, a['href']), re.I)]
            episodes = [(a.get_text(' ', strip=True) or a.get('title') or '播放', urljoin(address, a['href'])) for a in links]
            if not episodes:
                if CONFIG['media'] == 'images':
                    self._images(soup, address)
                else:
                    self._media(soup, address)  # Refuse non-content pages.
                episodes = [('阅读' if CONFIG['media'] == 'images' else '播放', address)]
            row.update(vod_play_from='默认线路', vod_play_url='#'.join(title.replace('$', ' ').replace('#', ' ') + '$' + quote(url, safe='') for title, url in episodes))
            return {'list': [row]}
        return self._api(ac='detail', ids=','.join(str(v) for v in ids))

    def _media(self, soup, base):
        for tag in soup.select('video[src],video source[src],source[src]'):
            url = urljoin(base, tag.get('src', ''))
            if url.startswith(('http://', 'https://')):
                return url
        for script in soup.select('script[type="application/ld+json"]'):
            try:
                values = json.loads(script.get_text())
                pending = values if isinstance(values, list) else [values]
                for value in pending:
                    if isinstance(value, dict) and value.get('@type') == 'VideoObject' and value.get('contentUrl'):
                        return urljoin(base, value['contentUrl'])
            except (ValueError, TypeError):
                pass
        # Public CMS JSON only; source JavaScript is never executed.
        for script in soup.select('script'):
            m = re.search(r'player_\w+\s*=\s*(\{.*?\})\s*;', script.get_text(), re.S)
            if m:
                try:
                    v = json.loads(m[1]); url = v.get('url', '')
                    if str(v.get('encrypt', 0)) == '2':
                        import base64
                        url = base64.b64decode(url).decode()
                    if str(v.get('encrypt', 0)) in ('1', '2'):
                        url = unquote(url)
                    if re.search(r'\.(mp4|m3u8|webm|mpd)(?:[?#]|$)', url, re.I):
                        return urljoin(base, url)
                except (ValueError, TypeError):
                    pass
        raise ValueError('PY 也未识别到公开媒体；需站点专用适配')

    def _images(self, soup, base):
        selector = CONFIG.get('imageSelector')
        if not selector:
            root = soup.find(id=CONFIG['contentId']) if CONFIG.get('contentId') else soup
            selector = 'img' if CONFIG.get('contentId') else 'article img,.reading-content img,.comic-content img,#content img'
        else:
            root = soup
        images = []
        for image in root.select(selector) if root else []:
            value = next((image.get(key) for key in ('data-original', 'data-lazy-src', 'data-src', 'src') if image.get(key) and not image.get(key).startswith('data:')), '')
            if image.get('srcset'):
                value = image['srcset'].split(',')[-1].strip().split()[0]
            address = urljoin(base, value)
            if value and address.startswith(('http://', 'https://')) and address not in images:
                images.append(address)
        if not images:
            raise ValueError('漫画 PY 没有识别到阅读区图片，请调整图片解析规则')
        return images

    def imageContent(self, id):
        address = unquote(id)
        soup = BeautifulSoup(self._get(address), 'html.parser')
        return {'images': self._images(soup, address), 'headers': {'Referer': address}}

    def playerContent(self, flag, id, vipFlags=None):
        if CONFIG['media'] == 'images':
            return self.imageContent(id)
        if not id.startswith(('http://', 'https://')):
            id = unquote(id)
        if not re.search(r'\.(mp4|m3u8|webm|mpd)(?:[?#]|$)', id, re.I):
            id = self._media(BeautifulSoup(self._get(id), 'html.parser'), id)
        return {'parse': 0, 'url': id, 'header': {'Referer': CONFIG['url']}}

    def getName(self):
        return CONFIG['name']

    def destroy(self):
        pass
