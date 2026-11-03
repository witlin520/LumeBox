"""Build the bundled offline voice from only its hash-locked runtime files.

The upstream archive remains accepted for manual import. No model weights,
speakers, normalization rules or synthesis settings are changed.
"""
import argparse
import hashlib
import json
import io
from pathlib import Path
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def digest(file):
    with Path(file).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def prepare(asset_root):
    asset_root = Path(asset_root)
    manifest = json.loads((asset_root / 'manifest.json').read_text('utf8'))
    runtime = asset_root / 'runtime'
    runtime.mkdir(parents=True, exist_ok=True)
    cached = runtime / 'manifest.json'
    if cached.exists():
        saved = json.loads(cached.read_text('utf8'))
        if saved.get('sourceSha256') == manifest['archiveSha256'] and all(
            (runtime / part['name']).exists() and
            (runtime / part['name']).stat().st_size == part['bytes'] and
            digest(runtime / part['name']) == part['sha256']
            for part in saved['parts']
        ):
            return saved
    wanted = {item['name']: item for item in manifest['files']}
    with tempfile.TemporaryDirectory(prefix='speech-pack-') as temporary:
        temporary = Path(temporary)
        upstream = temporary / 'source.tar.bz2'
        with upstream.open('wb') as sink:
            for part in manifest['parts']:
                file = asset_root / part['name']
                if digest(file) != part['sha256'] or file.stat().st_size != part['bytes']:
                    raise ValueError(f'Upstream part mismatch: {file}')
                with file.open('rb') as stream:
                    while chunk := stream.read(1024 * 1024):
                        sink.write(chunk)
        if digest(upstream) != manifest['archiveSha256']:
            raise ValueError('Upstream archive mismatch')
        compact = temporary / 'runtime.tar.bz2'
        seen = set()
        with tarfile.open(upstream, 'r:bz2') as source, tarfile.open(compact, 'w:bz2') as target:
            for entry in source:
                name = entry.name.replace('\\', '/').split('/')[-1]
                if name not in wanted or not entry.isfile():
                    continue
                if name in seen or entry.size != wanted[name]['bytes']:
                    raise ValueError(f'Duplicate or wrong-sized runtime file: {name}')
                # The runtime files are bounded by the pinned manifest; verify
                # before publishing any prepared assets.
                content = source.extractfile(entry).read()
                if hashlib.sha256(content).hexdigest() != wanted[name]['sha256']:
                    raise ValueError(f'Runtime file mismatch: {name}')
                normalized = tarfile.TarInfo('vits-zh-aishell3/' + name)
                normalized.size = len(content)
                normalized.mode = 0o644
                target.addfile(normalized, io.BytesIO(content))
                seen.add(name)
        if seen != wanted.keys():
            raise ValueError('Upstream archive is missing runtime files')
        parts = []
        with compact.open('rb') as stream:
            while chunk := stream.read(32 * 1024 * 1024):
                name = f'pack.{len(parts):02d}'
                pending = runtime / (name + '.tmp')
                pending.write_bytes(chunk)
                pending.replace(runtime / name)
                parts.append({'name': name, 'bytes': len(chunk), 'sha256': hashlib.sha256(chunk).hexdigest()})
        result = {'sourceSha256': manifest['archiveSha256'], 'archiveSha256': digest(compact), 'parts': parts}
        pending = cached.with_suffix('.json.tmp')
        pending.write_text(json.dumps(result, indent=2) + '\n', 'utf8')
        pending.replace(cached)
        keep = {part['name'] for part in parts}
        for file in runtime.glob('pack.*'):
            if file.name not in keep:
                file.unlink()
        return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--asset-root', type=Path, default=ROOT / 'assets/speech/vits_aishell3')
    args = parser.parse_args()
    result = prepare(args.asset_root)
    print(f"Verified offline voice: {sum(part['bytes'] for part in result['parts']) / 1048576:.2f} MiB; unchanged runtime hashes")
