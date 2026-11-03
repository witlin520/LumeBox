"""Inventory every source; optionally probe icons on ordinary movie/audio sites.

Does not execute adapters, download feeds, or request adult-site media.
"""
import argparse
import concurrent.futures
import html.parser
import json
import pathlib
import re
import urllib.parse
import urllib.request


class HeadImages(html.parser.HTMLParser):
    def __init__(self, base):
        super().__init__()
        self.base, self.icons, self.covers = base, [], []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'base' and a.get('href'):
            self.base = urllib.parse.urljoin(self.base, a['href'])
        if tag == 'link' and 'icon' in a.get('rel', '') and a.get('href'):
            self.icons.append(urllib.parse.urljoin(self.base, a['href']))
        if tag == 'meta' and a.get('property', a.get('name')) in ('og:image', 'twitter:image') and a.get('content'):
            self.covers.append(urllib.parse.urljoin(self.base, a['content']))


def fetch(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Accept': '*/*'})
    with urllib.request.urlopen(req, timeout=7) as response:
        return response.url, response.headers.get('Content-Type', ''), response.read(524288)


def raster(data):
    return (data.startswith((b'\x89PNG\r\n\x1a\n', b'\xff\xd8\xff', b'GIF87a', b'GIF89a', b'\0\0\1\0'))
            or data[:4] == b'RIFF' and data[8:12] == b'WEBP')


def probe(row):
    result = {'id': row['id'], 'path': row['path'], 'site': row['site']}
    try:
        final, _, body = fetch(row['site'])
        parser = HeadImages(final)
        parser.feed(body.decode('utf-8', errors='replace'))
        candidates = list(dict.fromkeys([*row['icons'], *parser.icons,
            urllib.parse.urljoin(final, '/favicon.ico'), urllib.parse.urljoin(final, '/favicon.png')]))
        attempts = []
        for url in candidates[:6]:
            try:
                resolved, kind, data = fetch(url)
                if raster(data):
                    result.update(iconStatus='verified-raster', icon=resolved)
                    break
                attempts.append({'url': url, 'status': 'svg' if 'svg' in kind else 'not-raster'})
            except Exception as error:
                attempts.append({'url': url, 'status': type(error).__name__})
        else:
            result['iconStatus'] = 'unverified'
        result['iconAttempts'] = attempts
        result['homepageCoverDeclared'] = bool(parser.covers)
        # Homepage social artwork is not proof that individual item covers work.
        result['itemCovers'] = 'not-live-tested'
    except Exception as error:
        result.update(iconStatus='homepage-unreachable', error=type(error).__name__, itemCovers='not-live-tested')
    return result


def inventory(root):
    catalog = json.loads((root / 'metadata/catalog.json').read_text(encoding='utf-8'))
    rows = catalog['sources']
    for row in rows:
        text = (root / row['path']).read_text(encoding='utf-8-sig')
        meta = json.loads(re.search(r'LumeSource\s*:\s*(\{[^\n]+\})', text)[1])
        site = (meta.get('mirrors') or [''])[0]
        if not site:
            match = re.search(r'''\b(?:BASE_URL|BASE|HOST|baseURL|baseUrl|base_url|base|host|H\.base)\s*[:=]\s*['"](https?://[^'"]+)''', text)
            if match:
                site = match[1]
        if not site:
            match = re.search(r'''HOSTS\s*=\s*\[\s*['"](https?://[^'"]+)''', text)
            if match:
                site = match[1]
        row['site'] = site
        row['icons'] = [urllib.parse.urljoin(site, meta[key]) for key in ('icon', 'iconUrl') if isinstance(meta.get(key), str)]
        row['coverHeadersDeclared'] = 'coverHeaders' in text
    return rows


if __name__ == '__main__':
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('repository', type=pathlib.Path)
    cli.add_argument('output', type=pathlib.Path)
    cli.add_argument('--live', action='store_true')
    args = cli.parse_args()
    rows = inventory(args.repository)
    ordinary = [r for r in rows if r['kind'] in ('movie', 'audiobook') and r['rating'] != '18+' and r['site']]
    probes = []
    if args.live:
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            for result in pool.map(probe, ordinary):
                probes.append(result)
                print(json.dumps({k: result.get(k) for k in ('id', 'iconStatus')}, ensure_ascii=False), flush=True)
    report = {'summary': {'sources': len(rows), 'adult': sum(r['rating'] == '18+' for r in rows),
        'missingExplicitIcon': sum(not r['icons'] for r in rows), 'liveProbed': len(probes),
        'verifiedIcons': sum(p['iconStatus'] == 'verified-raster' for p in probes)},
        'sources': rows, 'ordinarySiteChecks': probes,
        'limits': 'Local classification inventory for all sources; network checks only on ordinary movie/audio homepages and icons. Item covers are not inferred from declarations.'}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report['summary']), flush=True)
