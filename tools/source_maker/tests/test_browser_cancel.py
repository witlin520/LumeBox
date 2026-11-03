import io
import threading
import time
import unittest
from unittest.mock import patch

from browser_session import BrowserSession


class Process:
    def __init__(self):
        self.stdin, self.stdout = io.StringIO(), io.StringIO()
        self.stopped = False
    def poll(self):
        return 0 if self.stopped else None
    def terminate(self):
        self.stopped = True
    def wait(self, timeout=None):
        self.stopped = True
        return 0


class BrowserCancelTests(unittest.TestCase):
    def test_cancel_wakes_browser_initialization_without_waiting_for_webview(self):
        opened, session, errors = threading.Event(), [], []
        process = Process()
        def on_open(value):
            session.append(value)
            opened.set()
        def connect():
            try:
                BrowserSession('https://fixture.test/', on_open=on_open)
            except Exception as error:
                errors.append(error)
        with patch('browser_session.subprocess.Popen', return_value=process), patch.object(BrowserSession, '_read'):
            thread = threading.Thread(target=connect, daemon=True)
            thread.start()
            self.assertTrue(opened.wait(2))
            before = time.monotonic()
            session[0].cancel()
            thread.join(1)
            self.assertFalse(thread.is_alive())
            self.assertLess(time.monotonic() - before, 1)
        self.assertTrue(process.stopped)
        self.assertTrue(errors)

    def test_browser_startup_has_a_deadline(self):
        process = Process()
        with patch('browser_session.subprocess.Popen', return_value=process), patch.object(BrowserSession, '_read'), patch('browser_session.time.monotonic', side_effect=[0, 181]):
            with self.assertRaisesRegex(ValueError, '超时'):
                BrowserSession('https://fixture.test/')
        self.assertTrue(process.stopped)
