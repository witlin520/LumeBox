"""Materialize exports for tests that run the real Dart importers and engines."""
import json
import sys
from pathlib import Path

from core import discover, target_config
from exports import export_source


def make(directory):
    root = Path(directory)
    root.mkdir(parents=True, exist_ok=True)
    base = 'https://fixture.invalid'
    api = {'class': [{'type_id': '1', 'type_name': '影视'}], 'page': 1, 'pagecount': 2,
           'list': [{'vod_id': '1', 'vod_name': '接口作品', 'vod_pic': base + '/cover.jpg',
                     'vod_content': '介绍', 'vod_play_from': '线路',
                     'vod_play_url': '第一集$https://media.invalid/movie.mp4'}]}
    pages = {'/list': '<title>制源测试</title><nav><a href="/category/science">科普</a></nav><form action="/list" method="GET"><select name="area" aria-label="地区"><option value="">全部</option><option value="cn">中国</option></select></form><a href="/item/1"><img src="/cover.jpg" alt="测试作品"></a>',
             '/search': '<a href="/item/1" title="测试作品">测试作品</a>',
             '/item/1': '<h1>作品详情</h1><a href="/chapter/1">第一章</a><article><img src="/photo.jpg"></article>',
             '/chapter/1': '<article><audio src="https://media.invalid/book.mp3"></audio><video src="https://media.invalid/movie.mp4"></video><img src="/page.jpg"></article>',
             '/api': json.dumps(api)}
    pages['/category/science'] = pages['/list']

    class Fixture:
        def get(self, url):
            from urllib.parse import urlsplit
            return url, pages[urlsplit(url).path]

    c, rows, _ = discover(base + '/list', 'video', Fixture())
    c.update(search=base + '/search?q={keyword}', searchXPath="//a[contains(@href,'/item/')]", chapterXPath="//a[contains(@href,'/chapter/')]")
    manifest = []
    for target in ('audio', 'comic', 'images', 'video', 'module', 'cat', 'web', 'python', 'kazumi'):
        config = target_config(c, target)
        if target in ('python', 'kazumi'):
            config.update(mode='maccms', api=base + '/api')
        config['id'] = 'maker-' + target
        ext, raw, route = export_source(config, rows)
        filename = target + ext
        (root / filename).write_bytes(raw)
        manifest.append({'target': target, 'file': filename, 'category': config['category'], 'route': route})
    # HTML Kazumi follows a different browser/XPath path; test its importer too.
    k = target_config(c, 'kazumi')
    ext, raw, _ = export_source(k, rows)
    (root / 'kazumi-html.json').write_bytes(raw)
    py = target_config(c, 'python')
    (root / 'python-html.py').write_bytes(export_source(py, rows)[1])
    comic = target_config(c, 'comic_python')
    comic['imageSelector'] = 'article img'
    (root / 'comic-python.py').write_bytes(export_source(comic, rows)[1])
    browser = dict(c, useBrowser=True)
    (root / 'browser.js').write_bytes(export_source(browser, rows)[1])
    (root / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False), encoding='utf-8')
    (root / 'pages.json').write_text(json.dumps(pages, ensure_ascii=False), encoding='utf-8')


if __name__ == '__main__':
    make(sys.argv[1])
