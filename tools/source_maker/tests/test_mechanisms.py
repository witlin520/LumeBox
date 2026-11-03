import gzip
import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch
from urllib.parse import parse_qs, unquote, urlsplit

from core import BrowserRequired, Fetcher, discover, entry_redirect, generate, request_url
from exports import export_source
from verifier import execute, verify_config


class MediaCMS:
    def __init__(self):
        self.calls = []

    def get(self, url):
        self.calls.append(url)
        p, q = urlsplit(url), parse_qs(urlsplit(url).query)
        if p.path == '/':
            return url, "<title>Teaching</title><script>MediaCMS.site={api:'/api/v1'};MediaCMS.api={media:'/media'};</script>"
        if p.path.endswith('/categories'):
            data = [{'title': '科学 教学', 'uid': 'not-the-query-key', 'media_count': 1}]
        elif '/media/' in p.path:
            token = p.path.rsplit('/', 1)[1]
            data = {'url': 'https://example.test/view?m=' + token, 'friendly_token': token, 'title': 'Lesson',
                    'thumbnail_url': '/cover.jpg', 'encodings_info': {'720': {'h264': {'url': '/lesson.mp4', 'status': 'success'}}}}
        else:
            ids = ['two'] if q.get('c') == ['科学 教学'] or q.get('q') == ['中文'] else ['one', 'two']
            if q.get('sort_by') == ['views_desc']:
                ids.reverse()
            if q.get('upload_date') == ['today']:
                ids = []
            if q.get('page') == ['2']:
                ids = ['three']
            # This deployed API ignores duration on search; generator must filter it.
            rows = [{'url': 'https://example.test/view?m=' + token, 'friendly_token': token, 'title': 'Lesson ' + token,
                     'thumbnail_url': '/cover-' + token + '.jpg', 'duration': 600 if token != 'two' else 1800} for token in ids]
            if p.path.endswith('/media') and q.get('duration') == ['0-20']:
                rows = [x for x in rows if x['duration'] < 1200]
            data = {'results': rows, 'next': None if q.get('page') == ['2'] or len(rows) < 2 else '/api/v1/media?page=2'}
        return url, json.dumps(data, ensure_ascii=False)


class MechanismTests(unittest.TestCase):
    def test_mediacms_semantic_filters_categories_covers_and_stateless_detail(self):
        f = MediaCMS()
        c, rows, _ = discover('https://example.test/', fetcher=f)
        self.assertEqual(c['mode'], 'mediacms')
        self.assertFalse(c['useBrowser'])
        s = generate(c)
        out = execute(s, '''(async function(){var cats=await LumeSource.categories(),first=await LumeSource.list({page:1}),cat=await LumeSource.list({categoryId:cats[1].id}),sorted=await LumeSource.list({filters:{sort_by:'views_desc'}}),short=await LumeSource.list({filters:{duration:'0-20'}}),combined=await LumeSource.list({keyword:'中文',filters:{duration:'0-20'}}),empty=await LumeSource.list({filters:{upload_date:'today'}}),second=await LumeSource.list({page:2});return {first:first,cat:cat,sorted:sorted,short:short,combined:combined,empty:empty,second:second};})()''', f)
        self.assertTrue(out['first']['items'][0]['cover'].endswith('one.jpg'))
        self.assertEqual(out['cat']['items'][0]['apiToken'], 'two')
        self.assertEqual(out['sorted']['items'][0]['apiToken'], 'two')
        self.assertTrue(all(x['duration'] < 1200 for x in out['short']['items']))
        self.assertEqual(out['combined']['items'], [])
        self.assertEqual(out['empty']['items'], [])
        self.assertEqual(out['second']['items'][0]['apiToken'], 'three')
        params = [parse_qs(urlsplit(x).query) for x in f.calls]
        self.assertTrue(any(x.get('c') == ['科学 教学'] for x in params))
        media = execute(s, "LumeSource.content({id:'https://example.test/view?m=one'})", f)
        self.assertEqual(media['url'], 'https://example.test/lesson.mp4')
        self.assertEqual(media['headers']['Referer'], 'https://example.test/view?m=one')
        self.assertIn('列表封面', verify_config(c, rows, f))
        with self.assertRaisesRegex(ValueError, '未支持的筛选值'):
            execute(s, "LumeSource.list({filters:{unknown:'x'}})", f)

    def test_public_api_module_and_unsupported_exports(self):
        f = MediaCMS()
        c, rows, _ = discover('https://example.test/', fetcher=f)
        c['target'] = 'module'
        self.assertIn('通过', verify_config(c, rows, f))
        c['target'] = 'python'
        with self.assertRaisesRegex(ValueError, '尚未通过验证'):
            export_source(c, rows)

    def test_wordpress_discovered_api_embedded_cover_and_category(self):
        class WP:
            def get(self, url):
                p, q = urlsplit(url), parse_qs(urlsplit(url).query)
                post = {'id': 7, 'title': {'rendered': 'Public &amp; teaching'}, 'content': {'rendered': '<video src="https://media.test/lesson.mp4"></video>'},
                        '_embedded': {'wp:featuredmedia': [{'source_url': 'https://media.test/cover.jpg'}]}}
                if p.path == '/':
                    return url, '<title>Teaching</title><link rel="https://api.w.org/" href="/wp-json/">'
                data = {'namespaces': ['wp/v2']} if p.path == '/wp-json/' else [{'id': 3, 'name': 'Science', 'count': 1}] if p.path.endswith('categories') else post if p.path.endswith('/7') else [post]
                return url, json.dumps(data)
        f = WP()
        c, rows, _ = discover('https://example.test/', fetcher=f)
        self.assertEqual(c['mode'], 'wordpress')
        self.assertIn('通过', verify_config(c, rows, f))
        content = execute(generate(c), "LumeSource.content({id:'7'})", f)
        self.assertTrue(content['headers']['Referer'].startswith('https://'))

    def test_ssr_next_initial_jsonld_and_no_arbitrary_code_execution(self):
        works = [{'url': '/item/one', 'title': 'Lesson One', 'image': '/one.jpg'}, {'url': '/item/two', 'title': 'Lesson Two', 'image': '/two.jpg'}]
        payload = json.dumps({'props': {'pageProps': {'works': works}}})
        for script in ['<script id="__NEXT_DATA__" type="application/json">' + payload + '</script>',
                       '<script>window.__INITIAL_STATE__=' + payload + ';</script>',
                       '<script type="application/ld+json">' + json.dumps({'@type': 'ItemList', 'itemListElement': [{'item': x} for x in works]}) + '</script>']:
            class SSR:
                def get(self, url):
                    return url, '<title>Teaching</title>' + script if url.endswith('/') else '<h1>Lesson</h1><script type="application/json">{"player":{"contentUrl":"https://media.test/lesson.mp4"}}</script>'
            f = SSR()
            c, rows, _ = discover('https://example.test/', fetcher=f)
            self.assertTrue(c['structuredList'])
            self.assertEqual(len(rows), 2)
            self.assertIn('通过', verify_config(c, rows, f))
        c['structuredList'] = True
        result = execute(generate(c), '''structuredItems('<script>window.__INITIAL_STATE__=(function(){throw new Error("executed")})();</script>',C.url)''')
        self.assertEqual(result, [])

    def test_literal_players_hls_jw_videojs_and_ads_are_not_scanned(self):
        c, _, _ = discover('https://example.test/', fetcher=MediaCMS())
        c.update(mode='html', structuredList=False)
        s = generate(c)
        fixtures = ['<video id="player"></video><script>var source="https://media.test/a.m3u8";hls.loadSource(source);</script>',
                    '<video></video><script>var source=decodeURIComponent(atob("aHR0cHM6Ly9tZWRpYS50ZXN0L2EubTN1OA=="));hls.loadSource(source);</script>',
                    '<video></video><script>hls.loadSource("https:\\/\\/media.test\\/a.m3u8");</script>',
                    '<script>jwplayer("x").setup({sources:[{file:"https://media.test/a.m3u8"}]});</script>',
                    '<video></video><script>videojs("x",{sources:[{src:"https://media.test/a.m3u8"}]});</script>']
        for html in fixtures:
            self.assertEqual(execute(s, 'media(' + json.dumps(html) + ',C.url)'), 'https://media.test/a.m3u8')
        for html in ['<video></video><script>var advertisement="https://ad.test/a.mp4";</script>',
                     '<video></video><script>var source="https://media.test/a.mp4"+privateSignature;hls.loadSource(source);</script>',
                     '<script type="application/ld+json">{"@type":"VideoObject","embedUrl":"https://player.test/embed"}</script>']:
            self.assertEqual(execute(s, 'media(' + json.dumps(html) + ',C.url)'), '')

    def test_nested_player_iframes_have_depth_limit_and_keep_player_referer(self):
        c, _, _ = discover('https://example.test/', fetcher=MediaCMS())
        c.update(mode='html')
        class Frames:
            def get(self, url):
                return url, '<video src="/lesson.mp4"></video>' if url.endswith('/embed/lesson') else '<div id="player"><iframe src="https://player.test/embed/lesson"></iframe></div>'
        result = execute(generate(c), "LumeSource.content({id:'https://example.test/work'})", Frames())
        self.assertEqual(result['url'], 'https://player.test/lesson.mp4')
        self.assertEqual(result['headers']['Referer'], 'https://player.test/embed/lesson')
        class Loop:
            def __init__(self):
                self.calls = 0
            def get(self, url):
                self.calls += 1
                return url, '<div class="player"><iframe src="/embed/' + str(self.calls) + '"></iframe></div>'
        f = Loop()
        with self.assertRaisesRegex(ValueError, '未找到公开'):
            execute(generate(c), "LumeSource.content({id:'https://example.test/work'})", f)
        self.assertLessEqual(f.calls, 3)

    def test_bootstrap_outer_link_filters_navigation_and_numeric_slug_families(self):
        class Cards:
            def get(self, url):
                if url.endswith('/'):
                    return url, '<title>Teaching</title><nav><a href="/work/search/science">Science</a></nav>' + ''.join('<a href="' + path + '"><div class="card"><h5>Lesson</h5><img src="data:image/gif;base64,AA" data-src="/cover.jpg"><a href="/work/search/tag">Tag</a></div></a>' for path in ['/work/search/science', '/work/123/first', '/work/124/second'])
                return url, '<h1>Lesson</h1><video src="https://media.test/lesson.mp4"></video>'
        f = Cards()
        c, rows, _ = discover('https://example.test/', fetcher=f)
        self.assertEqual(len(rows), 2)
        value = execute(generate(c), 'LumeSource.list({page:1})', f)
        self.assertEqual(len(value['items']), 2)
        self.assertTrue(all(x['cover'].endswith('/cover.jpg') for x in value['items']))

    def test_recommendation_episode_words_do_not_override_current_player(self):
        class Recommendations:
            def get(self, url):
                if url.endswith('/'):
                    return url, '<article class="video-card"><a href="/work/123/lesson">Lesson</a><img src="/cover.jpg"></article>'
                return url, '<h1>Lesson</h1><nav><a href="/work/search/science">Science</a></nav><video></video><script>var source="https://media.test/lesson.m3u8";hls.loadSource(source);</script><a href="/work/124/other">第十八集：推荐其他作品</a>'
        f = Recommendations()
        c, rows, _ = discover('https://example.test/', fetcher=f)
        self.assertNotIn('search', c['chapters'])
        chapters = execute(generate(c), 'LumeSource.chapters({id:' + json.dumps(rows[0]['id']) + '})', f)
        self.assertEqual(chapters, [{'id': rows[0]['id'], 'title': '播放'}])
        self.assertIn('通过', verify_config(c, rows, f))

    def test_gateway_stubs_are_unambiguous_and_loops_stop(self):
        self.assertEqual(entry_redirect('<script>window.location="https://actual.test/";</script>', 'https://entry.test/'), 'https://actual.test/')
        self.assertEqual(entry_redirect('<meta http-equiv="refresh" content="0;url=/home">', 'https://entry.test/'), 'https://entry.test/home')
        self.assertIsNone(entry_redirect('<a href="/work">Lesson</a><script>location="https://ad.test";</script>', 'https://entry.test/'))
        self.assertIsNone(entry_redirect('<script>location="https://a.test"; location="https://b.test";</script>', 'https://entry.test/'))
        class Gate:
            def get(self, url):
                if url == 'https://entry.test/':
                    return url, '<a href="/gate/1">Entry one</a><a href="/gate/2">Entry two</a>'
                if '/gate/' in url:
                    return url, '<script>location="https://actual.test/";</script>'
                return url, '<div id="app"></div>'
        with self.assertRaises(BrowserRequired) as error:
            discover('https://entry.test/', fetcher=Gate())
        self.assertEqual(error.exception.target_url, 'https://actual.test/')

    def test_rss_and_atom_enclosures_do_not_treat_articles_as_media(self):
        for body in ['<rss><channel><title>Podcast</title><itunes:image href="/cover.jpg"/><item><title><![CDATA[Public lesson]]></title><enclosure url="https://media.test/stream" type="audio/mpeg"/></item><item><title>Article</title><link>https://article.test</link></item></channel></rss>',
                     '<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Public lesson</title><link rel="enclosure" href="https://media.test/stream" type="audio/mpeg"/></entry></feed>']:
            class Feed:
                def get(self, url):
                    return url, body
            f = Feed()
            c, rows, _ = discover('https://example.test/feed', 'audio', f)
            self.assertEqual(c['mode'], 'feed')
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]['title'], 'Public lesson')
            self.assertIn('通过', verify_config(c, rows, f))
            with self.assertRaisesRegex(ValueError, '未提供'):
                execute(generate(c), "LumeSource.list({keyword:'lesson'})", f)


class NetworkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.counts = {}
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass
            def do_GET(self):
                path = unquote(urlsplit(self.path).path)
                cls.counts[path] = cls.counts.get(path, 0) + 1
                if path == '/busy' and cls.counts[path] == 1 or path in ('/wait', '/cancel'):
                    self.send_response(503 if path == '/busy' else 429)
                    self.send_header('Retry-After', '0' if path == '/busy' else '60' if path == '/wait' else '2')
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                raw = ('<title>中文</title>' * (2000 if path == '/bomb' else 1)).encode()
                if path in ('/gzip', '/bomb'):
                    raw = gzip.compress(raw)
                    self.send_header('Content-Encoding', 'gzip')
                self.end_headers()
                self.wfile.write(raw)
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f'http://127.0.0.1:{cls.server.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def test_chinese_urls_preserve_escapes_and_idna(self):
        f = Fetcher()
        self.assertIn('中文', f.get(self.url + '/中文?q=中文')[1])
        self.assertNotIn('%25', request_url(self.url + '/%E4%B8%AD?q=%E6%96%87'))
        self.assertIn('xn--', request_url('https://中文.test/中文'))

    def test_gzip_and_bounded_decompression(self):
        self.assertIn('中文', Fetcher().get(self.url + '/gzip')[1])
        with patch('core.MAX_BYTES', 1024), self.assertRaisesRegex(ValueError, '解压'):
            Fetcher().get(self.url + '/bomb')

    def test_transient_retry_long_retry_after_and_cancel_during_backoff(self):
        self.assertIn('中文', Fetcher().get(self.url + '/busy')[1])
        self.assertEqual(self.counts['/busy'], 2)
        with self.assertRaisesRegex(ValueError, '等待'):
            Fetcher().get(self.url + '/wait')
        self.assertEqual(self.counts['/wait'], 1)
        cancel = threading.Event()
        timer = threading.Timer(.1, cancel.set)
        timer.start()
        with self.assertRaises(InterruptedError):
            Fetcher(cancel).get(self.url + '/cancel')
        timer.join()
        self.assertEqual(self.counts['/cancel'], 1)
