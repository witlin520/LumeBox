import io
import json
import queue
import threading
import unittest
from unittest.mock import Mock

from browser_session import BrowserSession, CurrentPageFetcher, LIMIT


class CurrentPageTests(unittest.TestCase):
    def session(self, result):
        session = BrowserSession.__new__(BrowserSession)
        session.url = 'https://fixture.test/'
        session.lock = threading.Lock()
        session.closed = threading.Event()
        session.ready = True
        session.worker = Mock()
        session.worker.poll.return_value = None
        session.worker.stdin = io.StringIO()
        session.events = queue.Queue()
        session.events.put(result)
        return session

    def test_capture_reads_without_navigation(self):
        session = self.session({'ok': True, 'url': 'https://fixture.test/videos', 'html': '<main>list</main>'})
        self.assertEqual(session.current_page(), ('https://fixture.test/videos', '<main>list</main>'))
        self.assertEqual(json.loads(session.worker.stdin.getvalue()), {'action': 'snapshot'})

    def test_foreign_page_and_oversized_dom_are_rejected(self):
        for result, error in (({'ok': True, 'url': 'https://other.test/', 'html': ''}, '其他站点'),
                              ({'ok': True, 'url': 'https://fixture.test/', 'html': 'x' * (LIMIT + 1)}, '6MB'),
                              ({'ok': False, 'error': '需要验证'}, '需要验证')):
            with self.subTest(error=error), self.assertRaisesRegex(ValueError, error):
                self.session(result).current_page()

    def test_entry_uses_snapshot_and_detail_uses_live_browser(self):
        browser = Mock()
        browser.browser_mode = True
        browser.get.return_value = ('https://fixture.test/item/1', '<video></video>')
        fetcher = CurrentPageFetcher(browser, 'https://fixture.test/catalogue', '<article>list</article>')
        self.assertTrue(fetcher.browser_mode)
        self.assertEqual(fetcher.get('https://fixture.test/catalogue', purpose='list')[1], '<article>list</article>')
        browser.get.assert_not_called()
        self.assertEqual(fetcher.get('https://fixture.test/item/1', purpose='media')[1], '<video></video>')
        browser.get.assert_called_once_with('https://fixture.test/item/1', purpose='media')
