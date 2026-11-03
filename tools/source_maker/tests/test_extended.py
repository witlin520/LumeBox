import json
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from core import discover, generate, target_config
from verifier import execute, verify_config, verify_with_fallback


class Pages:
    def __init__(self):
        self.calls = []
    def get(self, url):
        self.calls.append(url)
        path = url.split('example.test', 1)[-1]
        if path == '/':
            body = '<title>公开教学视频</title><article class="video-card"><a href="/item/1">查看</a><h3>教学一</h3><img data-src="/cover.jpg"></article><a rel="next" href="/page-two">下一页</a>'
        elif path == '/page-two':
            body = '<article class="video-card"><a href="/item/2">查看</a><h3>教学二</h3><img src="/cover2.jpg"></article>'
        elif path.startswith('/item/'):
            body = '<h1>教学详情</h1><script type="application/ld+json">' + json.dumps({'@type': 'VideoObject', 'contentUrl': 'https://media.test/lesson.mp4'}) + '</script>'
        elif path == '/comic':
            body = '<title>公开漫画</title><div class="manga-card"><h3>漫画一</h3><a href="/book/1">详情</a><img src="/book.jpg"></div>'
        elif path == '/book/1':
            body = '<h1>漫画一</h1><div class="chapter-list"><a href="/read/one">第1话</a></div>'
        elif path == '/read/one':
            body = '<img src="/advert.jpg"><div class="reading-content"><img data-original="/one.jpg"><img srcset="/two.jpg 1x, /two-big.jpg 2x"></div>'
        else:
            raise ValueError(url)
        return url, body


class ExtendedTests(unittest.TestCase):
    def test_adaptive_rules_are_saved_only_after_learning_and_export_new_css(self):
        from adaptive_rules import AdaptiveProfiles, AdaptiveFetcher
        with tempfile.TemporaryDirectory() as directory:
            profiles = AdaptiveProfiles(directory)
            pages = Pages()
            fetcher = AdaptiveFetcher(pages, profiles)
            c, rows, _ = discover('https://example.test/', 'video', fetcher)
            self.assertEqual(profiles.recover('<div>empty</div>', c['url'], 'listSelector'), ('', []))
            profiles.learn(c, rows, fetcher)
            changed = '<title>公开教学视频</title><article class="updated-card"><a href="/item/1">查看</a><h3>教学一</h3><img data-src="/cover.jpg"></article><article class="updated-card"><a href="/item/2">查看</a><h3>教学二</h3><img data-src="/cover2.jpg"></article>'
            from rule_detection import inferred_cards
            rules, recovered = inferred_cards(changed, c['url'], profiles)
            self.assertEqual(rules['listSelector'], 'article.updated-card')
            self.assertEqual(len(recovered), 2)
            script = generate(dict(c, **rules))
            class Changed(Pages):
                def get(self, url):
                    return (url, changed) if url == c['url'] else super().get(url)
            self.assertEqual(len(execute(script, 'LumeSource.list({page:1})', Changed())['items']), 2)
            self.assertEqual(profiles.recover(changed, 'https://other.test/', 'listSelector'), ('', []))
            profiles.forget(c['url'])
            self.assertEqual(profiles.recover(changed, c['url'], 'listSelector'), ('', []))

    def test_network_diagnostics_redact_tokens_and_export_actions(self):
        from browser_actions import network_row
        value = network_row('https://example.test/api?token=private&q=lesson', 200, {'token':'private','data':{'password':'private','title':'lesson'}})
        self.assertNotIn('private', json.dumps(value))
        c, rows, _ = discover('https://example.test/', 'video', Pages())
        c.update(useBrowser=True, browserActions={'click':'#more','clicks':2,'scroll':1})
        script = generate(c)
        self.assertIn('browserDocument', script)
        self.assertIn('"click": "#more"', script)

    def test_scrapling_cards_and_real_next_page(self):
        pages = Pages()
        c, rows, _ = discover('https://example.test/', 'video', pages)
        self.assertEqual(c['desktopParser'], 'Scrapling')
        self.assertEqual(rows[0]['title'], '教学一')
        self.assertEqual(rows[0]['cover'], 'https://example.test/cover.jpg')
        result = execute(generate(c), '(async function(){await LumeSource.list({page:1});return LumeSource.list({page:2});})()', pages)
        self.assertEqual(result['items'][0]['title'], '教学二')
        self.assertIn('https://example.test/page-two', pages.calls)
        self.assertIn('通过', verify_config(c, rows, pages))

    def test_inferred_comic_chapters_and_scoped_lazy_images(self):
        pages = Pages()
        c, rows, _ = discover('https://example.test/comic', 'comic', pages)
        self.assertEqual(c['chapterSelector'], '.chapter-list a')
        self.assertEqual(c['imageSelector'], '.reading-content img')
        result = execute(generate(c), 'LumeSource.content({chapterId:"https://example.test/read/one"})', pages)
        self.assertEqual(len(result['images']), 2)
        self.assertNotIn('https://example.test/advert.jpg', result['images'])
        self.assertIn('通过', verify_config(c, rows, pages))

    def test_python_html_and_js_first(self):
        pages = Pages()
        c, rows, _ = discover('https://example.test/', 'video', pages)
        checked, report = verify_with_fallback(c, rows, pages)
        self.assertEqual(checked['target'], 'video')
        self.assertIn('通过', report)
        py = target_config(c, 'python')
        self.assertIn('PY Spider', verify_config(py, rows, pages))

    def test_python_fallback_for_selector_beyond_js_subset(self):
        pages = Pages()
        c, rows, _ = discover('https://example.test/', 'video', pages)
        c['listSelector'] = 'article.video-card:not(.advert)'
        with self.assertRaises(ValueError):
            verify_with_fallback(c, rows, pages)
        self.assertEqual(c['target'], 'video')
        checked, report = verify_with_fallback(c, rows, pages, allow_python=True)
        self.assertEqual(checked['target'], 'python')
        self.assertIn('备用', report)
        self.assertIn('确认', report)

    def test_comic_python_exports_images_only_after_opt_in(self):
        from exports import export_source
        pages = Pages()
        c, rows, _ = discover('https://example.test/comic', 'comic', pages)
        c['imageSelector'] = '.reading-content img:not(.advert)'
        with self.assertRaises(ValueError):
            verify_with_fallback(c, rows, pages)
        checked, report = verify_with_fallback(c, rows, pages, allow_python=True)
        self.assertEqual(checked['target'], 'comic_python')
        self.assertEqual(checked['category'], 'comic')
        suffix, raw, route = export_source(checked, rows)
        self.assertEqual(suffix, '.py')
        self.assertIn('漫画', route)
        namespace = {}
        exec(compile(raw, 'comic.py', 'exec'), namespace)
        spider = namespace['Spider']()
        spider._get = lambda url: pages.get(url)[1]
        images = spider.imageContent('https://example.test/read/one')
        self.assertEqual(images['images'], ['https://example.test/one.jpg', 'https://example.test/two-big.jpg'])


if __name__ == '__main__':
    import sys
    from browser_check import browser_checks
    print(json.dumps(browser_checks(sys.argv[1]), ensure_ascii=True))
