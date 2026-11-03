import base64
import json
import unittest
from urllib.parse import urlsplit, parse_qs
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.padding import PKCS7

from core import discover, generate
from verifier import execute, verify_config


class PublicYeguo:
    def __init__(self, locked=False):
        self.locked = locked
        self.calls = []

    def get(self, url):
        return url, '<title>野果短剧</title><a href="/drama/detail/7/"><img src="/cover.png" alt="测试剧"></a>'

    def request(self, options):
        args = parse_qs(options['body'], keep_blank_values=True)
        self.calls.append((options['url'], args))
        assert args['token'] == ['']
        assert len(args['oauth_id'][0]) == 32
        path = urlsplit(options['url']).path
        if path.endswith('/exploreList'):
            data = {'list': [{'video_id': 8 if args.get('theme') == ['7'] or args.get('setting') == ['23'] else 7, 'title': '测试剧', 'cover': 'https://example.test/cover.png'}], 'total': 1,
                    'filters':[{'key':'theme','title':'主题','options':[{'value':7,'name':'原创'}]}, {'key':'setting','title':'设定','options':[{'value':23,'name':'剧情'}]}]}
        elif path.endswith('/detail'):
            assert args['video_id'] == ['7']
            data = {'video_id': 7, 'title': '测试剧', 'episodes': [{'id': 91, 'sort': 1, 'access': {'can_play': not self.locked}}]}
        elif path.endswith('/play'):
            assert args['episode_id'] == ['91']
            data = {'video_url': '' if self.locked else 'https://cdn.test/granted.m3u8', 'access': {'can_play': not self.locked}}
        else:
            raise AssertionError(path)
        raw = json.dumps({'status': 1, 'data': data}, ensure_ascii=False).encode()
        pad = PKCS7(128).padder()
        cipher = Cipher(algorithms.AES(b'2acf7e91e9864673'), modes.CBC(b'1c29882d3ddfcfd6')).encryptor()
        return {'status': 200, 'body': json.dumps({'data': base64.b64encode(cipher.update(pad.update(raw) + pad.finalize()) + cipher.finalize()).decode()})}


class YeguoTests(unittest.TestCase):
    def test_public_envelope_episode_id_and_granted_media(self):
        f = PublicYeguo()
        config, rows, _ = discover('https://yeguodj.com/', fetcher=f)
        self.assertEqual(config['mode'], 'yeguo')
        self.assertEqual(config['contentCategory'], 'adult')
        result = execute(generate(config), "(async function(){var chapters=await LumeSource.chapters({id:'7'});return await LumeSource.content({id:'7',chapterId:chapters[0].id});})()", f)
        self.assertEqual(result['url'], 'https://cdn.test/granted.m3u8')
        config_script = generate(config)
        out = execute(config_script, "(async function(){var cats=await LumeSource.categories(),filters=await LumeSource.filters(),list=await LumeSource.list({categoryId:'theme:7',filters:{setting:'23'}});return {cats:cats,filters:filters,list:list};})()", f)
        self.assertEqual(len(out['cats']), 2)
        self.assertEqual(out['filters']['groups'][0]['id'], 'setting')
        self.assertEqual(out['list']['items'][0]['id'], '8')
        self.assertEqual(out['list']['items'][0]['coverHeaders']['x-lume-image-encoding'], 'aes-cbc-pkcs7')
        self.assertIn('已提取媒体地址', verify_config(config, rows, f))

    def test_locked_episode_falls_back_to_site_and_search_is_explicit(self):
        f = PublicYeguo(locked=True)
        config, rows, _ = discover('https://yeguodj.com/', fetcher=f)
        result = execute(generate(config), "LumeSource.content({id:'7',chapterId:'91:1'})", f)
        self.assertEqual(result['kind'], 'webplayer')
        self.assertIn('/drama/video/7/ep-1/', result['pageUrl'])
        with self.assertRaisesRegex(ValueError, '搜索尚未适配'):
            execute(generate(config), "LumeSource.list({keyword:'test'})", f)


if __name__ == '__main__':
    unittest.main()
