import json
import unittest
from urllib.parse import urlsplit

from core import discover, generate
from exports import export_source
from verifier import execute, verify_config


class DramaAPI:
    def __init__(self, locked=False):
        self.calls = []
        self.locked = locked

    def get(self, url):
        if '/api/' not in url:
            return url, '<title>短剧</title><script src="/assets/index.js"></script>'
        return url, json.dumps({'list': [{'id': 7, 'title': '测试剧', 'cover': '/cover.jpg'}], 'total': 1})

    def request(self, options):
        self.calls.append(options)
        path = urlsplit(options['url']).path
        if path.endswith('/auth/guest'):
            body = json.loads(options['body'])
            assert len(body['requestKey']) == 43
            assert options['method'] == 'POST'
            data = {'token': 'guest-token'}
        else:
            assert options['headers']['Authorization'] == 'Bearer guest-token'
            if path.endswith('/home'):
                data = {'categories': [{'id': 3, 'name': '都市'}]}
            elif path.endswith('/episodes/1'):
                data = {'episode': {'id': 11, 'number': 1, 'locked': self.locked,
                                    'video_url': '' if self.locked else 'https://cdn.test/granted.m3u8'}}
            elif path.endswith('/episodes'):
                data = {'list': [{'id': 11, 'number': 1, 'access_type': 'free'}]}
            elif path.endswith('/dramas/7'):
                data = {'drama': {'id': 7, 'title': '测试剧', 'cover': '/cover.jpg'}}
            else:
                data = {'list': [{'id': 7, 'title': '测试剧', 'cover': '/cover.jpg'}], 'total': 1}
        return {'status': 200, 'body': json.dumps({'data': data})}


class ZhilianTests(unittest.TestCase):
    def test_discovery_generated_js_and_guest_playback(self):
        f = DramaAPI()
        config, rows, note = discover('https://yklyo880.lldj1.xyz/pc/', fetcher=f)
        self.assertEqual(config['mode'], 'zhilian')
        self.assertEqual(config['contentCategory'], 'adult')
        self.assertEqual(rows[0]['id'], '7')
        script = generate(config)
        self.assertNotIn('unlockUrl', script)
        content = execute(script, "LumeSource.content({id:'7',chapterId:'1:11'})", f)
        self.assertEqual(content['url'], 'https://cdn.test/granted.m3u8')
        self.assertIn('已提取媒体地址', verify_config(config, rows, f))
        self.assertEqual(export_source(config, rows)[0], '.js')

    def test_locked_player_report_does_not_claim_direct_playback(self):
        f = DramaAPI(locked=True)
        config, rows, _ = discover('https://yklyo880.lldj1.xyz/pc/', fetcher=f)
        report = verify_config(config, rows, f)
        self.assertIn('直连媒体 0 条、源站网页播放 1 条', report)
        self.assertIn('权限和实际播放未验证', report)
        config['target'] = 'python'
        with self.assertRaisesRegex(ValueError, '保持 JS'):
            export_source(config, rows)


if __name__ == '__main__':
    unittest.main()
