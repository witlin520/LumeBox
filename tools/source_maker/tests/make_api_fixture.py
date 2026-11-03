"""Export real generated JS/module bytes plus deterministic public CMS responses."""
import json
import sys
from pathlib import Path
from urllib.parse import parse_qsl, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core import discover, target_config
from exports import export_source
from test_mechanisms import MediaCMS
from test_payload_routes import NuxtPages, QueryWordPress
from platforms import api_path

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
f = MediaCMS()
c, rows, _ = discover('https://example.test/', fetcher=f)
for target in ('video', 'module'):
    config = target_config(c, target)
    config['id'] = 'maker-api-' + target
    ext, raw, _ = export_source(config, rows)
    (root / (target + ext)).write_bytes(raw)
responses = {}
for suffix in ['/categories', '/media?page=1&media_type=video', '/media?page=2&media_type=video',
               '/media?page=1&media_type=video&sort_by=views_desc', '/media?page=1&media_type=video&duration=0-20',
               '/media?page=1&media_type=video&upload_date=today', '/search?page=1&media_type=video&c=%E7%A7%91%E5%AD%A6%20%E6%95%99%E5%AD%A6',
               '/search?page=1&media_type=video&q=%E4%B8%AD%E6%96%87', '/media/one', '/media/two']:
    url = c['api'] + suffix
    p = urlsplit(url)
    key = p.path + '?' + json.dumps(sorted(parse_qsl(p.query)), ensure_ascii=False, separators=(',', ':'))
    responses[key] = f.get(url)[1]
for name, fixture, base in [('nuxt', NuxtPages(), 'https://example.test/'),
                            ('wordpress', QueryWordPress(), 'https://example.test/blog/')]:
    config, items, _ = discover(base, fetcher=fixture)
    config['id'] = 'maker-api-' + name
    ext, raw, _ = export_source(config, items)
    (root / (name + ext)).write_bytes(raw)
    if name == 'nuxt':
        urls = [base, base + 'item/one', base + 'item/two']
    else:
        urls = [api_path(config['api'], '/categories', {'per_page': 100, 'hide_empty': 'true'}),
                api_path(config['api'], '/posts/7', {'_embed': 1})]
        common = {'page': 1, 'per_page': 20, '_embed': 1, 'orderby': 'date', 'order': 'desc'}
        for extra in ({}, {'categories': 3}, {'order': 'asc'}, {'search': '中文'}):
            urls.append(api_path(config['api'], '/posts', dict(common, **extra)))
    for url in urls:
        p = urlsplit(url)
        key = p.path + '?' + json.dumps(sorted(parse_qsl(p.query)), ensure_ascii=False, separators=(',', ':'))
        responses[key] = fixture.get(url)[1]
(root / 'responses.json').write_text(json.dumps(responses, ensure_ascii=False), encoding='utf8')

from test_yeguo import PublicYeguo
f = PublicYeguo()
c, rows, _ = discover('https://yeguodj.com/', fetcher=f)
c['id'] = 'maker-api-yeguo'
ext, raw, _ = export_source(c, rows)
(root / ('yeguo' + ext)).write_bytes(raw)
public = {}
from urllib.parse import urlencode
for path, args in [('/api/theater/exploreList', {}), ('/api/playlet/detail', {'video_id':7}), ('/api/playlet/play', {'video_id':7,'episode_id':91})]:
    opts = {'url': c['api'] + path, 'method':'POST', 'body':urlencode(dict(token='',oauth_id='a'*32,**args))}
    public['/api.php'+path] = f.request(opts)['body']
(root / 'yeguo-responses.json').write_text(json.dumps(public), encoding='utf-8')

from test_inline_media import Cards
f = Cards()
c, rows, _ = discover('https://example.test/', fetcher=f)
c['id'] = 'maker-api-inline'
ext, raw, _ = export_source(c, rows)
(root / ('inline' + ext)).write_bytes(raw)
(root / 'inline.html').write_text(f.get(c['url'])[1], encoding='utf-8')
