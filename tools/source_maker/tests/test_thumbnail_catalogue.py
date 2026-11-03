import unittest
from core import discover, generate
from verifier import execute, verify_config


class ThumbnailCatalogue:
    def __init__(self, known=True):
        self.known = known

    def get(self, url):
        if '/video/' in url:
            return url, '<h1>Fixture video</h1><video id="player"><source src="https://cdn.test/fixture/master.m3u8" type="application/x-mpegURL"></video>'
        menu = '<nav>' + ''.join(f'<a href="/show/topic-{i}">Topic {i}</a>' for i in range(200)) + '</nav>'
        cards = ''.join(
            f'<div class="{"onevideothumb" if self.known else "custom-entry"}"><a class="{"clip-link" if self.known else "detail"}" href="/video/{i}/sample-{i}/"><img src="/cover/{i}.jpg" alt="Fixture {i}"></a></div>'
            for i in range(1, 5))
        return url, '<title>Fixture catalogue</title>' + menu + cards


class ThumbnailCatalogueTests(unittest.TestCase):
    def assert_catalogue(self, known):
        f = ThumbnailCatalogue(known)
        config, rows, _ = discover('https://example.test/', fetcher=f)
        self.assertEqual(len(rows), 4)
        self.assertTrue(all('/video/' in row['id'] and row['cover'] for row in rows))
        self.assertIn('/video/', config['links'].replace('\\', ''))
        self.assertEqual(config['target'], 'video')
        script = generate(config)
        listed = execute(script, 'LumeSource.list({page:1})', f)['items']
        self.assertEqual([r['id'] for r in listed], [r['id'] for r in rows])
        self.assertTrue(all(r['cover'] for r in listed))
        cats = execute(script, 'LumeSource.categories()', f)
        self.assertEqual(len(cats), 201)
        self.assertIn('通过 3 条', verify_config(config, rows, f))

    def test_thumbnail_card_list_is_not_replaced_by_large_taxonomy_menu(self):
        self.assert_catalogue(True)

    def test_unknown_card_layout_prefers_multiple_visual_works_to_plain_menu_links(self):
        self.assert_catalogue(False)
