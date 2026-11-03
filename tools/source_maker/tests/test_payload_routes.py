"""Behavior checks for Nuxt references and non-pretty WordPress permalinks."""
import json
import unittest
from urllib.parse import parse_qs, urlsplit

from core import discover, generate
from platforms import api_path
from verifier import execute, verify_config


def nuxt_catalog():
    return [['ShallowReactive', 1], {'data': 2, 'state': 14}, ['ShallowReactive', 3],
            {'catalog': 4}, [5, 9], {'url': 6, 'title': 7, 'image': 8}, '/item/one',
            'Lesson One', '/one.jpg', {'url': 10, 'title': 11, 'image': 12},
            '/item/two', 'Lesson Two', '/two.jpg', False, ['Reactive', 15],
            {'counter': 16, 'zero': -6, 'missing': -1, 'nested': 17}, 123, ['Ref', 18], 'loaded']


class NuxtPages:
    def __init__(self, multi_app=False):
        self.multi_app = multi_app

    def get(self, url):
        identity = 'data-nuxt-data="app"' if self.multi_app else 'id="__NUXT_DATA__"'
        data = nuxt_catalog() if url.endswith('/') else [
            ['Reactive', 1], {'player': 2}, {'contentUrl': 3}, 'https://media.test/lesson.mp4']
        return url, '<title>Public teaching</title><script type="application/json" ' + identity + '>' + json.dumps(data) + '</script>'


class QueryWordPress:
    def __init__(self):
        self.calls = []

    def get(self, url):
        self.calls.append(url)
        p, q = urlsplit(url), parse_qs(urlsplit(url).query)
        if p.path == '/blog/' and not q:
            return url, '<title>Public teaching</title><link rel="https://api.w.org/" href="index.php?rest_route=/&amp;lang=zh">'
        if p.path != '/blog/index.php' or q.get('lang') != ['zh']:
            raise ValueError('REST endpoint lost its path or language query')
        route = q.get('rest_route', [''])[0]
        post = {'id': 7, 'link': 'https://example.test/blog/lesson/', 'title': {'rendered': 'Lesson'},
                'content': {'rendered': '<video src="../media/lesson.mp4"></video>'},
                '_embedded': {'wp:featuredmedia': [{'source_url': 'https://example.test/cover.jpg'}]}}
        if route == '/':
            data = {'namespaces': ['wp/v2']}
        elif route == '/wp/v2/categories':
            data = [{'id': 3, 'name': 'Science', 'count': 1}]
        elif route == '/wp/v2/posts/7':
            data = post
        elif route == '/wp/v2/posts':
            if q.get('categories') == ['3'] or q.get('order') == ['asc'] or q.get('search') == ['中文']:
                post = dict(post, id=8)
            data = [post]
        else:
            raise ValueError('Invalid REST route')
        return url, json.dumps(data)


class PayloadRouteTests(unittest.TestCase):
    def test_nuxt_single_and_multi_app_catalog_and_media_are_decoded(self):
        for multi in (False, True):
            f = NuxtPages(multi)
            c, rows, _ = discover('https://example.test/', fetcher=f)
            self.assertEqual(len(rows), 2)
            self.assertTrue(c['structuredList'])
            c['version'] = '1.0.1'
            s = generate(c)
            self.assertEqual(execute(s, 'LumeSource.version'), '1.0.1')
            self.assertEqual(execute(s, 'LumeSource.list({page:1})', f)['items'][0]['cover'], 'https://example.test/one.jpg')
            state = execute(s, 'nuxtPayload(' + json.dumps(nuxt_catalog()) + ').state')
            self.assertEqual(state, {'counter': 123, 'zero': 0, 'missing': None, 'nested': 'loaded'})
            self.assertIn('通过', verify_config(c, rows, f))

    def test_nuxt_malformed_references_and_custom_reducers_are_not_plain_data(self):
        c, _, _ = discover('https://example.test/', fetcher=NuxtPages())
        s = generate(c)
        for malformed in [[{'works': 90000}], [[0.5]], [['Reactive', 0]],
                          [{'__proto__': 1}, {'polluted': 2}, True], [[-7, 999999999]]]:
            with self.assertRaises(ValueError):
                execute(s, 'nuxtPayload(JSON.parse(' + json.dumps(json.dumps(malformed)) + '))')
            html = '<script id="__NUXT_DATA__" type="application/json">' + json.dumps(malformed) + '</script>'
            self.assertEqual(execute(s, 'structuredItems(' + json.dumps(html) + ',C.url)'), [])
        table = [['CustomSiteReducer', 1], {'works': 2}, [3], {'url': 4, 'title': 5, 'image': 6}, '/item/one', 'Lesson', '/cover.jpg']
        self.assertIsNone(execute(s, 'nuxtPayload(' + json.dumps(table) + ')'))
        # An ordinary JSON array must not be reinterpreted as devalue without a Nuxt marker.
        html = '<script type="application/json">' + json.dumps([{'url': '/item/one', 'title': 'Lesson', 'image': '/cover.jpg'}]) + '</script>'
        self.assertEqual(len(execute(s, 'structuredItems(' + json.dumps(html) + ',C.url)')), 1)

    def test_nuxt_cycles_and_extreme_reference_chains_are_bounded(self):
        c, _, _ = discover('https://example.test/', fetcher=NuxtPages())
        s = generate(c)
        cyclic = [{'data': 1, 'self': 0}, {'works': 2}, [3], {'url': 4, 'title': 5, 'image': 6}, '/item/one', 'Lesson', '/cover.jpg']
        html = '<script id="__NUXT_DATA__" type="application/json">' + json.dumps(cyclic) + '</script>'
        self.assertEqual(len(execute(s, 'structuredItems(' + json.dumps(html) + ',C.url)')), 1)
        chain = [['Ref', i + 1] for i in range(70)] + ['end']
        with self.assertRaisesRegex(ValueError, '超过解析范围'):
            execute(s, 'nuxtPayload(' + json.dumps(chain) + ')')

    def test_wordpress_query_permalink_keeps_routes_filters_search_and_media(self):
        f = QueryWordPress()
        c, rows, _ = discover('https://example.test/blog/', fetcher=f)
        self.assertEqual(c['mode'], 'wordpress')
        self.assertEqual(parse_qs(urlsplit(c['api']).query)['rest_route'], ['/wp/v2'])
        s = generate(c)
        out = execute(s, '''(async function(){return {list:await LumeSource.list({}),category:await LumeSource.list({categoryId:'category:3'}),oldest:await LumeSource.list({filters:{sort_by:'oldest'}}),search:await LumeSource.list({keyword:'中文'}),content:await LumeSource.content({id:'7'})};})()''', f)
        self.assertEqual(out['list']['items'][0]['id'], '7')
        for key in ('category', 'oldest', 'search'):
            self.assertEqual(out[key]['items'][0]['id'], '8')
        self.assertEqual(out['content']['url'], 'https://example.test/blog/media/lesson.mp4')
        self.assertEqual(out['content']['headers']['Referer'], 'https://example.test/blog/lesson/')
        self.assertTrue(all(parse_qs(urlsplit(x).query).get('lang') == ['zh'] for x in f.calls if 'index.php' in x))
        self.assertIn('通过', verify_config(c, rows, f))

    def test_pretty_rest_paths_also_preserve_public_query_parameters(self):
        self.assertEqual(api_path('https://example.test/wp-json/?lang=zh', '/wp/v2'), 'https://example.test/wp-json/wp/v2?lang=zh')
        self.assertEqual(api_path('https://example.test/?rest_route=/wp/v2', '/posts', {'page': 2}), 'https://example.test/?rest_route=%2Fwp%2Fv2%2Fposts&page=2')

    def test_wordpress_total_pages_and_out_of_range_do_not_break_pagination(self):
        c, _, _ = discover('https://example.test/blog/', fetcher=QueryWordPress())
        posts = [{'id': i + 1, 'title': {'rendered': 'Lesson'}} for i in range(20)]
        setup = '''LumeSource.http={get:async function(url){return {status:200,body:BODY,headers:{'X-WP-TotalPages':'1'}};}};'''.replace('BODY', json.dumps(json.dumps(posts)))
        result = execute(generate(c), '(async function(){' + setup + 'return LumeSource.list({page:1});})()')
        self.assertEqual(len(result['items']), 20)
        self.assertFalse(result['hasMore'])
        error = "LumeSource.http={get:async function(){return {status:400,body:'{\"code\":\"rest_post_invalid_page\"}'};}};"
        self.assertEqual(execute(generate(c), '(async function(){' + error + 'return LumeSource.list({page:2});})()'), {'items': [], 'hasMore': False})
        with self.assertRaisesRegex(ValueError, 'HTTP 400'):
            execute(generate(c), '(async function(){' + error + 'return LumeSource.list({page:1});})()')
