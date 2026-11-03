"""Reproduce the pinned local-service adapter; never accepts an unpinned update."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1] / 'assets/local_danmaku'
manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8'))
data = Path(sys.argv[1]).read_bytes()
if hashlib.sha256(data).hexdigest() != manifest['upstreamReleaseSha256']:
    raise SystemExit('Upstream SHA-256 does not match the pinned release')
source = data.decode('utf-8')
for before, after in manifest['patches']:
    if before not in source:
        raise SystemExit('Upstream adapter anchor is missing')
    source = source.replace(before, after)
data = source.encode('utf-8')
if hashlib.sha256(data).hexdigest() != manifest['patchedSha256']:
    raise SystemExit('Patched SHA-256 mismatch')
(root / 'upstream.cjs').write_bytes(data)
print('Pinned local danmaku adapter reproduced and verified')
