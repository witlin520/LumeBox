import json
import unittest

from bs4 import BeautifulSoup
from core import site_name, discover, generate
from exports import export_source
from verifier import execute


class IdentityTests(unittest.TestCase):
    def test_brand_title_drops_domain_and_cms_suffix(self):
        soup = BeautifulSoup('<title>360资源站【360zy.com】 - 苹果cms - 海洋cms - 影视站采集</title>', 'html.parser')
        self.assertEqual('360资源站', site_name(soup, 'https://360zy.com/'))

    def test_site_brand_beats_detail_title_and_preserves_meaningful_brackets(self):
        soup = BeautifulSoup('<meta property="og:site_name" content="示例（典藏版）"><title>电影 - 站点 - 更多</title>', 'html.parser')
        self.assertEqual('示例（典藏版）', site_name(soup, 'https://example.test'))
        self.assertEqual('example.test', site_name(BeautifulSoup('', 'html.parser'), 'https://example.test'))

    def test_export_declares_js_and_keeps_metadata_first(self):
        class Pages:
            def get(self, url):
                return url, '<title>示例 - 视频</title><a href="/item/1"><img src="/a.jpg" alt="示例作品"></a><video src="https://media.test/a.mp4"></video>'
        config, rows, _ = discover('https://example.test/', 'video', Pages())
        script = generate(config)
        self.assertEqual('示例', json.loads(script.splitlines()[0].split(': ', 1)[1])['name'])
        self.assertEqual('// LumeRuntime: javascript', script.splitlines()[1])
        extension, data, _ = export_source(config, rows)
        self.assertEqual('.js', extension)
        self.assertNotIn(b'# LumeRuntime: python', data)

    def test_numeric_spa_player_links_are_chapters(self):
        class Pages:
            def get(self, url):
                if '/drama/' in url:
                    return url, '<a class="cell" href="/pc/pages/player/player?id=one&episode=1&episodeId=e1">1</a>'
                return url, '<title>示例</title><article class="card"><a href="/pc/pages/drama/drama?id=one"><img src="/cover.jpg" alt="作品"></a></article>'
        pages = Pages()
        config, rows, _ = discover('https://example.test/pc/', 'video', pages)
        self.assertIn('episode=', config['chapterSelector'])
        result = execute(generate(config), 'LumeSource.chapters({id:' + json.dumps(rows[0]['id']) + '})', pages)
        self.assertEqual(1, len(result))
        self.assertIn('episodeId=e1', result[0]['id'])

    def test_js_content_category_is_exported_without_changing_runtime(self):
        class Pages:
            def get(self, url):
                return url, '<title>示例</title><a href="/item/1"><img src="/c.jpg" alt="作品"></a>'
        config, _, _ = discover('https://example.test/', 'video', Pages())
        for category in ('movie', 'adult', 'unclassified'):
            script = generate(dict(config, contentCategory=category))
            metadata = json.loads(script.splitlines()[0].split(': ', 1)[1])
            self.assertEqual(category, metadata['contentCategory'])
            self.assertEqual('// LumeRuntime: javascript', script.splitlines()[1])


if __name__ == '__main__':
    unittest.main()
