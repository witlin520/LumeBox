from base.spider import Spider
from helpers import TITLE


class Spider(Spider):
    def homeContent(self, filter):
        return {'class': [{'type_id': 'demo', 'type_name': TITLE}]}

    def homeVideoContent(self):
        return {'list': [{'vod_id': 'one', 'vod_name': TITLE}]}

    def detailContent(self, ids):
        return {'list': [{'vod_id': ids[0], 'vod_name': TITLE,
                          'vod_play_from': '演示', 'vod_play_url': '代理示例$one'}]}

    def playerContent(self, flag, id, vipFlags):
        return {'parse': 0, 'url': self.getProxyUrl() + '&id=' + id}

    def localProxy(self, params):
        # This is a protocol example, not a real video stream.
        return [200, 'text/plain; charset=utf-8', TITLE]
