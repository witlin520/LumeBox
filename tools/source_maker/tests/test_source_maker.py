import json
import queue
import shutil
import subprocess
import tempfile
import threading
import unittest
import zipfile
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

from core import Fetcher, discover, generate, validate_url
from verifier import execute, verify


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        if self.path == '/msg':
            self.server.messages.put(json.loads(body))
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{}')

    def do_GET(self):
        path = urlsplit(self.path).path
        query = parse_qs(urlsplit(self.path).query)
        charset = 'utf-8'
        status = 200
        if path in ('/', '/page', '/search'):
            name = query.get('q', ['测试作品'])[0]
            body = f'''<title>测试站</title><nav><a href="/login">登录</a></nav>
              <a href="/book/1"><img data-src="/cover.jpg" alt="{name}"></a>
              <a href="/book/1">重复标题</a><a href="/book/2" title="第二本">第二本</a>
              <a href="?page=2">下一页</a>'''
        elif path.startswith('/book/'):
            body = '<h1>作品详情</h1><a href="/chapter/1">第一章</a><a href="/chapter/2">第二章</a>'
        elif path.startswith('/chapter/'):
            body = '<nav>无关导航</nav><article id="content"><audio src="/media/book.mp3"></audio><div><p>内容</p></div><img data-src="../image/1.jpg"><img src="/image/2.jpg"></article>'
        elif path == '/nested':
            body = '<div id="content"><div>嵌套开头</div><p>后半正文</p><img src="/end.jpg"></div><img src="/advert.jpg">'
        elif path == '/video':
            body = '<title>影片站</title><a href="/movie/1"><img src="/cover.jpg" alt="电影"></a>'
        elif path in ('/catalog', '/category/science'):
            number = '2' if query.get('region') == ['cn'] or path.startswith('/category') else '1'
            body = '<title>公开示例 - 视频目录 | 完整标题</title><nav><a href="/category/science">科普</a></nav><form method="GET" action="/catalog"><label for="region">地区</label><select id="region" name="region"><option value="">全部</option><option value="cn">中国</option><option value="us">美国</option></select></form>' + f'<a href="/movie/{number}"><img src="/cover.jpg" alt="作品 {number}"></a>'
        elif path == '/mixed':
            body = '<a href="/movie/1">有效作品</a><a href="/movie/bad">错误候选</a>'
        elif path == '/movie/bad':
            body = '<h1>普通人物介绍</h1><p>这里没有作品、选集或媒体内容</p>'
        elif path in ('/movie/1', '/movie/2'):
            body = '<h1>电影</h1><video><source src="/media/movie.mp4"></video>'
        elif path == '/encoded':
            body = '<script>var player_aaaa={"encrypt":2,"url":"aHR0cHM6Ly9tZWRpYS5leGFtcGxlL21vdmllLm0zdTg="};</script>'
        elif path == '/api':
            data = {'class': [{'type_id': 1, 'type_name': '电影'}], 'pagecount': 2, 'list': [{'vod_id': 1, 'vod_name': '接口影片', 'vod_pic': '/cover.jpg', 'vod_play_from': '线路一$$$线路二', 'vod_play_url': '第一集$https://media.example/1.mp4#第二集$https://media.example/2.mp4$$$第一集$https://media.example/b.mp4', 'vod_content': '<p>影片介绍</p>'}]}
            body = json.dumps(data)
        elif path == '/gbk':
            body, charset = '<title>中文网站</title><a href="/book/1">中文标题</a>', 'gbk'
        elif path == '/empty':
            body = '<div id="app"></div>'
        else:
            body, status = 'not found', 404
        self.send_response(status)
        self.send_header('Content-Type', 'text/html; charset=' + charset)
        self.end_headers()
        self.wfile.write(body.encode(charset))


class SourceMakerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.server.messages = queue.Queue()
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f'http://127.0.0.1:{cls.server.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def make(self, path='/', category='audio'):
        config, rows, _ = discover(self.base + path, category)
        return config, generate(config), rows

    def test_html_chain_and_dedup(self):
        c, script, rows = self.make()
        self.assertEqual(2, len(rows))
        self.assertEqual(self.base + '/cover.jpg', rows[0]['cover'])
        self.assertIn('通过', verify(script))
        value = execute(script, "LumeSource.content({id:C.url,chapterId:C.url+'chapter/1'})")
        self.assertEqual('audio', value['kind'])
        self.assertEqual(self.base + '/media/book.mp3', value['url'])

    def test_pagination_and_unicode_search(self):
        c, _, _ = self.make()
        c.update(list=self.base + '/page?page={page}', search=self.base + '/search?q={keyword}&page={page}')
        script = generate(c)
        result = execute(script, "LumeSource.list({page:2,keyword:'中文搜索'})")
        self.assertEqual('中文搜索', result['items'][0]['title'])
        self.assertTrue(result['hasMore'])

    def test_unconfigured_search_and_page(self):
        _, script, _ = self.make()
        self.assertFalse(execute(script, 'LumeSource.list({page:2})')['hasMore'])
        with self.assertRaisesRegex(ValueError, '尚未配置搜索'):
            execute(script, "LumeSource.list({keyword:'foo'})")

    def test_comic_images_and_relative_paths(self):
        c, _, _ = self.make(category='comic')
        c['contentId'] = 'content'
        result = execute(generate(c), "LumeSource.content({chapterId:C.url+'chapter/1'})")
        self.assertEqual([self.base + '/image/1.jpg', self.base + '/image/2.jpg'], result['images'])

    def test_video_and_base64(self):
        c, script, _ = self.make('/video', 'video')
        self.assertIn('通过', verify(script))
        result = execute(script, "LumeSource.content({chapterId:abs('/encoded')})")
        self.assertEqual('https://media.example/movie.m3u8', result['url'])

    def test_cms_chain(self):
        c, script, _ = self.make('/api', 'video')
        self.assertEqual('maccms', c['mode'])
        self.assertIn('通过', verify(script))
        chapters = execute(script, "LumeSource.chapters({id:'1'})")
        self.assertEqual(3, len(chapters))
        self.assertIn('线路二', chapters[2]['title'])
        self.assertTrue(execute(script, 'LumeSource.list({page:1})')['hasMore'])
        self.assertFalse(execute(script, 'LumeSource.list({page:2})')['hasMore'])

    def test_cms_url_parameters_do_not_override_detail_requests(self):
        c, _, _ = self.make('/api?ac=list&pg=1&token=test', 'video')
        self.assertEqual(self.base + '/api?token=test', c['api'])

    def test_module_export_can_run_in_tool(self):
        from core import target_config
        from verifier import verify_config
        c, _, rows = self.make('/video', 'video')
        self.assertIn('通过', verify_config(target_config(c, 'module'), rows))

    def test_category_navigation_does_not_outvote_content(self):
        from core import guess_pattern
        from urllib.parse import urljoin
        rows = [{'id': urljoin(self.base, '/category/' + str(i)), 'title': '栏目', 'cover': self.base + '/cover.jpg'} for i in range(100)]
        rows += [{'id': urljoin(self.base, '/c/' + str(i)), 'title': '分类', 'cover': ''} for i in range(100)]
        rows += [{'id': urljoin(self.base, '/item/' + str(i)), 'title': '作品', 'cover': ''} for i in range(3)]
        import re
        pattern = guess_pattern(rows, self.base)
        self.assertTrue(re.search(pattern, self.base + '/item/1'))
        self.assertFalse(re.search(pattern, self.base + '/category/1'))
        self.assertFalse(re.search(pattern, self.base + '/c/1'))

    def test_live_categories_filters_and_selected_list(self):
        from core import Fetcher
        c, script, _ = self.make('/catalog', 'video')
        categories = execute(script, 'LumeSource.categories()')
        self.assertEqual('科普', categories[1]['title'])
        groups = execute(script, 'LumeSource.filters()')['groups']
        self.assertEqual('地区', groups[0]['title'])
        self.assertEqual('cn', groups[0]['options'][1]['id'])
        result = execute(script, "LumeSource.list({categoryId:abs('/category/science'),page:1})")
        self.assertEqual('作品 2', result['items'][0]['title'])
        result = execute(script, "LumeSource.list({filters:{region:'cn'},page:1})")
        self.assertEqual('作品 2', result['items'][0]['title'])
        self.assertIn('筛选 1', verify(script))
        with self.assertRaisesRegex(ValueError, '未适配的筛选项'):
            execute(script, "LumeSource.list({filters:{unknown:'a'}})")

    def test_multiple_samples_prevent_false_success(self):
        _, script, _ = self.make('/mixed', 'video')
        with self.assertRaisesRegex(ValueError, '选集（样本 2/2）失败'):
            verify(script)

    def test_site_title_and_safe_export_filename(self):
        from core import source_filename
        c, _, _ = self.make('/catalog', 'video')
        self.assertEqual('公开示例', c['name'])
        self.assertEqual('公开示例.js', source_filename(c, '.js'))
        self.assertEqual('_CON.js', source_filename({'name':'CON','id':'id'}, '.js'))
        self.assertEqual('源 _ 标题.js', source_filename({'name':'源 / 标题. ','id':'id'}, '.js'))

    def test_gbk_and_errors(self):
        _, body = Fetcher().get(self.base + '/gbk')
        self.assertIn('中文标题', body)
        with self.assertRaisesRegex(ValueError, 'HTTP 404'):
            Fetcher().get(self.base + '/missing')
        with self.assertRaisesRegex(ValueError, '动态加载'):
            discover(self.base + '/empty')

    def test_validation(self):
        self.assertEqual('https://example.com', validate_url('example.com'))
        for value in ('file:///tmp/a', 'https://user:pass@example.com', 'http://'):
            with self.assertRaises(ValueError):
                validate_url(value)
        c, _, _ = self.make()
        c['id'] = '非法 ID'
        with self.assertRaises(ValueError):
            generate(c)

    def test_nested_content_and_missing_id(self):
        c, _, _ = self.make(category='comic')
        c['contentId'] = 'content'
        result = execute(generate(c), "LumeSource.content({chapterId:abs('/nested')})")
        self.assertEqual([self.base + '/end.jpg'], result['images'])
        c['contentId'] = 'missing'
        with self.assertRaisesRegex(ValueError, '找不到正文元素'):
            execute(generate(c), "LumeSource.content({chapterId:abs('/nested')})")

    def test_root_url_without_slash(self):
        _, script, _ = self.make()
        self.assertEqual('https://example.com/book', execute(script, "Promise.resolve(abs('book','https://example.com'))"))

    def test_export_formats_and_legacy_rejection(self):
        from core import target_config
        from exports import export_source
        c, _, rows = self.make()
        for target, suffix in [('audio', '.js'), ('comic', '.js'), ('images', '.js'), ('video', '.js'), ('module', '.cjs'), ('cat', '.zip'), ('web', '.html')]:
            extension, raw, route = export_source(target_config(c, target), rows)
            self.assertEqual(suffix, extension)
            self.assertTrue(raw)
            self.assertTrue(route)
        c['category'] = 'novel'
        with self.assertRaisesRegex(ValueError, '文字小说'):
            generate(c)

    @unittest.skipUnless(shutil.which('node'), 'Node is required for the development cat bootstrap test')
    def test_cat_real_app_bootstrap_and_endpoints(self):
        from core import target_config
        from exports import export_source
        from urllib.request import Request, urlopen
        c, _, rows = self.make('/video', 'video')
        _, raw, _ = export_source(target_config(c, 'cat'), rows)
        root = Path(__file__).resolve().parents[3]
        with tempfile.TemporaryDirectory(prefix='lume-maker-cat-') as tmp:
            folder = Path(tmp)
            import io
            with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                archive.extractall(folder)
            spec = {'bridgePort': self.server.server_port, 'token': 'development-test',
                    'sources': [{'id': 'maker-test', 'index': str(folder / 'index.js'), 'config': str(folder / 'index.config.js'), 'dataRoot': str(folder)}]}
            (folder / 'spec.json').write_text(json.dumps(spec), encoding='utf-8')
            process = subprocess.Popen(['node', str(root / 'assets/cat/bootstrap.js'), str(folder / 'spec.json')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                address = None
                for _ in range(10):
                    event = self.server.messages.get(timeout=10)
                    if event['action'] == 'sourceError':
                        self.fail(str(event))
                    if event['action'] == 'sourceStarted':
                        address = event['opt']['address']
                        break
                self.assertTrue(address, 'App bootstrap did not report sourceStarted')

                def call(path, data=None):
                    req = Request(address + path, data=json.dumps(data).encode() if data is not None else None,
                                  headers={'Content-Type': 'application/json'})
                    with urlopen(req, timeout=8) as response:
                        return json.load(response)
                config = call('/config')
                self.assertEqual('video', config['video']['sites'][0]['kind'])
                home = call('/source/home', {})
                first = home['list'][0]
                detail = call('/source/detail', {'id': first['vod_id']})['list'][0]
                episode = detail['vod_play_url'].split('$', 1)[1]
                content = call('/source/play', {'id': episode})
                self.assertEqual(self.base + '/media/movie.mp4', content['url'])
                self.assertEqual(0, content['parse'])
            finally:
                process.terminate()
                process.wait(timeout=10)


if __name__ == '__main__':
    unittest.main()
