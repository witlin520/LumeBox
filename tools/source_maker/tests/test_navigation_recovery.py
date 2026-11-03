import unittest
from browser_engines import playwright_snapshot, navigation_interrupted, SNAPSHOT_SCRIPT


class Page:
    def __init__(self, errors):
        self.errors = list(errors)
        self.waits = []
        self.scripts = []

    def evaluate(self, script):
        self.scripts.append(script)
        if self.errors:
            raise self.errors.pop(0)
        return {'html': '<main>list</main>', 'ready': 'complete', 'ua': 'fixture'}

    def wait_for_timeout(self, value):
        self.waits.append(value)


class NavigationTests(unittest.TestCase):
    def test_snapshot_recovers_when_redirect_destroys_the_old_context(self):
        page = Page([RuntimeError('Execution context was destroyed, most likely because of a navigation'),
                     RuntimeError('Cannot find context with specified id')])
        value = playwright_snapshot(page)
        self.assertEqual(value['html'], '<main>list</main>')
        self.assertEqual(page.waits, [250, 250])
        self.assertEqual(page.scripts, [SNAPSHOT_SCRIPT] * 3)

    def test_permanent_failure_does_not_spin_or_replay_actions(self):
        page = Page([RuntimeError('Target page, context or browser has been closed')])
        with self.assertRaisesRegex(RuntimeError, 'closed'):
            playwright_snapshot(page)
        self.assertEqual(page.waits, [])
        self.assertEqual(len(page.scripts), 1)

    def test_redirect_retry_is_bounded(self):
        page = Page([RuntimeError('Execution context was destroyed')] * 10)
        with self.assertRaisesRegex(RuntimeError, 'destroyed'):
            playwright_snapshot(page, attempts=3)
        self.assertEqual(len(page.scripts), 3)
        self.assertEqual(len(page.waits), 2)

    def test_only_known_navigation_failures_are_transient(self):
        self.assertTrue(navigation_interrupted('Navigation interrupted by another navigation'))
        self.assertTrue(navigation_interrupted('net::ERR_ABORTED'))
        self.assertFalse(navigation_interrupted('net::ERR_CERT_AUTHORITY_INVALID'))
        self.assertFalse(navigation_interrupted('SyntaxError: Unexpected token'))
