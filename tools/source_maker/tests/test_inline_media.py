import unittest
from core import discover, generate
from verifier import execute, verify_config

class Cards:
    def get(self, url):
        if '.mp4' in url:
            raise AssertionError('Discovery must not download a video as HTML')
        html = '<title>Example Media Feed</title><a href="/channel/one"><img src="/nav.png">频道</a>'
        for i in range(3):
            html += f'<div class="card"><video data-src="https://cdn.test/{i}.mp4" poster="https://cdn.test/{i}.jpg" aria-label="视频 {i}"></video></div>'
        return url, html

class InlineMediaTests(unittest.TestCase):
    def test_inline_html5_feed_ignores_navigation_and_preserves_cover_referer(self):
        f = Cards()
        config, rows, _ = discover('https://example.test/', fetcher=f)
        self.assertEqual(config['mode'], 'inline-media')
        self.assertEqual(len(rows), 3)
        self.assertTrue(all(x['id'].endswith('.mp4') for x in rows))
        self.assertTrue(all(x['coverHeaders']['Referer'] == 'https://example.test/' for x in rows))
        result = execute(generate(config), "(async function(){var list=await LumeSource.list({page:1}),item=list.items[0],detail=await LumeSource.detail({id:item.id}),chapters=await LumeSource.chapters({id:item.id});return await LumeSource.content({id:item.id,chapterId:chapters[0].id});})()", f)
        self.assertEqual(result['url'], 'https://cdn.test/0.mp4')
        self.assertIn('通过 3 条', verify_config(config, rows, f))

    def test_single_player_is_not_misclassified_as_feed(self):
        class Single:
            def get(self,url):
                if '/item/' in url:
                    return url,'<h1>视频</h1><video data-src="https://cdn.test/one.mp4"></video>'
                return url,'<title>Example</title><a href="/item/one"><img src="/cover.png">视频</a>'
        config, _, _ = discover('https://example.test/',fetcher=Single())
        self.assertNotEqual(config['mode'],'inline-media')

if __name__ == '__main__':
    unittest.main()
