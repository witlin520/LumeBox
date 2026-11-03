"""Resource packing regression checks; uses tiny local fixtures only."""
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

from prepare_speech_assets import prepare, digest


class SpeechPackingTest(unittest.TestCase):
    def fixture(self, root, *, bad_file=False):
        model = b'unchanged voice weights' * 64
        upstream = root / 'upstream.tar.bz2'
        with tarfile.open(upstream, 'w:bz2') as archive:
            for name, content in [('vits-aishell3.onnx', model), ('rule.far', b'unused' * 256)]:
                entry = tarfile.TarInfo('upstream/' + name)
                entry.size = len(content)
                archive.addfile(entry, io.BytesIO(content))
        data = upstream.read_bytes()
        (root / 'pack.00').write_bytes(data)
        metadata = {
            'archiveSha256': digest(upstream),
            'parts': [{'name': 'pack.00', 'bytes': len(data), 'sha256': digest(upstream)}],
            'files': [{'name': 'vits-aishell3.onnx', 'bytes': len(model),
                       'sha256': 'bad' if bad_file else hashlib.sha256(model).hexdigest()}],
        }
        (root / 'manifest.json').write_text(json.dumps(metadata), 'utf8')
        return model, data

    def test_exact_runtime_bytes_and_deterministic_rebuild(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            model, original = self.fixture(root)
            packed = prepare(root)
            parts = [root / 'runtime' / part['name'] for part in packed['parts']]
            joined = b''.join(part.read_bytes() for part in parts)
            self.assertEqual(hashlib.sha256(joined).hexdigest(), packed['archiveSha256'])
            with tarfile.open(fileobj=io.BytesIO(joined), mode='r:bz2') as archive:
                self.assertEqual(archive.getnames(), ['vits-zh-aishell3/vits-aishell3.onnx'])
                self.assertEqual(archive.extractfile(archive.getmembers()[0]).read(), model)
            self.assertEqual((root / 'pack.00').read_bytes(), original)
            self.assertEqual(prepare(root), packed)
            parts[0].write_bytes(b'corrupted cache')
            self.assertEqual(prepare(root), packed)
            self.assertEqual(parts[0].read_bytes(), joined)

    def test_bad_upstream_and_bad_runtime_hash_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root, bad_file=True)
            with self.assertRaisesRegex(ValueError, 'Runtime file mismatch'):
                prepare(root)
            self.fixture(root)
            (root / 'pack.00').write_bytes(b'broken')
            with self.assertRaisesRegex(ValueError, 'Upstream part mismatch'):
                prepare(root)


if __name__ == '__main__':
    unittest.main()
