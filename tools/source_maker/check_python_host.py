"""Development-only integration check against the App's unchanged Python host."""
import base64
import json
import sys
import types
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.cache/python-source-runtime/packages'))
sys.path.insert(0, str(ROOT / 'assets/python'))


def check(directory):
    directory = Path(directory)
    pages = json.loads((directory / 'pages.json').read_text(encoding='utf-8'))
    calls = []

    def invoke(raw):
        request = json.loads(raw)
        assert request['method'] == 'http', request
        calls.append(request)
        body = pages[urlsplit(request['payload']['url']).path].encode()
        return json.dumps({'ok': True, 'value': {'status': 200, 'headers': {'Content-Type': 'application/json; charset=utf-8'}, 'body': base64.b64encode(body).decode()}})

    native = types.ModuleType('_lume_host')
    native.invoke = invoke
    sys.modules['_lume_host'] = native
    import lume_python

    def dispatch(action, **payload):
        result = lume_python.execute(json.dumps({'sourceId': 'maker-python-test', 'action': action, 'timeout': 15, **payload}))
        assert result['ok'], result
        return result['value']

    loaded = dispatch('load', script=(directory / 'python.py').read_text(encoding='utf-8'))
    assert 'content' in loaded['methods']
    categories = dispatch('call', method='categories')
    assert categories[0]['title'] == '影视'
    listing = dispatch('call', method='list', argument={'keyword': '中文', 'page': 1})
    item = listing['items'][0]
    assert item['title'] == '接口作品'
    detail = dispatch('call', method='detail', argument={'id': item['id']})
    assert detail['title'] == '接口作品'
    chapters = dispatch('call', method='chapters', argument={'id': item['id']})
    content = dispatch('call', method='content', argument={'id': item['id'], 'chapterId': chapters[0]['id']})
    assert content['kind'] == 'video' and content['url'] == 'https://media.invalid/movie.mp4', content
    dispatch('dispose')
    dispatch('load', script=(directory / 'comic-python.py').read_text(encoding='utf-8'), section='comic')
    item = dispatch('call', method='list', argument={'page': 1})['items'][0]
    chapter = dispatch('call', method='chapters', argument={'id': item['id']})[0]
    images = dispatch('call', method='content', argument={'id': item['id'], 'chapterId': chapter['id']})
    assert images['kind'] == 'images' and images['images'] == ['https://fixture.invalid/page.jpg'], images
    assert images['imageHeaders'][images['images'][0]]['Referer'] == 'https://fixture.invalid/chapter/1', images
    dispatch('dispose')
    dispatch('load', script=(directory / 'python-html.py').read_text(encoding='utf-8'))
    listing = dispatch('call', method='list', argument={'page': 1})
    item = listing['items'][0]
    assert item['title'] == '测试作品', item
    groups = dispatch('call', method='filters', argument={})
    assert groups[0]['id'] == 'area', groups
    detail = dispatch('call', method='detail', argument={'id': item['id']})
    chapters = dispatch('call', method='chapters', argument={'id': item['id']})
    content = dispatch('call', method='content', argument={'id': item['id'], 'chapterId': chapters[0]['id']})
    assert content['kind'] == 'video' and content['url'] == 'https://media.invalid/movie.mp4', content
    dispatch('dispose')
    print(json.dumps({'ok': True, 'host': 'assets/python/lume_python.py', 'requests': len(calls), 'content': content, 'comic': images}, ensure_ascii=False))


if __name__ == '__main__':
    check(sys.argv[1])
