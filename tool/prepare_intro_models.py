"""Fetch pinned upstream models; run before a clean build if assets were removed.

MobileCLIP software MIT, weights Apple ASCL; YAMNet Apache-2.0.
Normal builds reuse verified anchor vectors and package only the image encoder.
Anchor regeneration uses Core ML on a Mac with --precompute.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/intro'
TEMP = ROOT / 'build/intro-models'
REVISION = '3e0a7bfb9fe83da8a3efaa3fd8f7df24214bb947'
FILES = {
    'mobileclip_s0_image.mlpackage/Data/com.apple.CoreML/model.mlmodel': '2c1afa132c41c6535817cc67894bd7484bc2cbd084ed5e2f12b24f611af17591',
    'mobileclip_s0_image.mlpackage/Data/com.apple.CoreML/weights/weight.bin': '87d8f63997bbd2f38ba7defeaaa2c571928bdece56aa9629542198b3ce906ed6',
    'mobileclip_s0_image.mlpackage/Manifest.json': 'fe07dde983dae92c1799132816ce55f9ff8487f2681b530abf7222025aa27fa4',
    'mobileclip_s0_text.mlpackage/Data/com.apple.CoreML/model.mlmodel': '81eba836ff4dbc8ae021d70006288b533ba7eed3c2973d245b0d5ea047305bfd',
    'mobileclip_s0_text.mlpackage/Data/com.apple.CoreML/weights/weight.bin': '34723e51445b2630106e94e1fdbebed80e7676b404fb839f4eb9bec97bdcad68',
    'mobileclip_s0_text.mlpackage/Manifest.json': 'a7cb0864a627468a953afd107262097ad74a0fcf82e49df7e00b9c86385bb7db',
}

def fetch(url, dest, digest=None):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        temp = dest.with_suffix(dest.suffix + '.partial')
        with urllib.request.urlopen(url, timeout=45) as response, temp.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        temp.replace(dest)
    actual = hashlib.sha256(dest.read_bytes()).hexdigest()
    if digest and actual != digest:
        raise ValueError(f'SHA-256 mismatch: {dest}')
    return actual

def tokens(vocab, merges, text):
    ranks = {tuple(line.split()): i for i, line in enumerate(merges.splitlines()[1:]) if len(line.split()) == 2 and ''.join(line.split()) in vocab}
    result = [vocab['<|startoftext|>']]
    # The bundled English anchors are ASCII; no byte-unicode remapping needed.
    for token in re.findall(r"'s|'t|'re|'ve|'m|'ll|'d|[a-z]+|[0-9]|[^\s\w]+", text.lower()):
        pieces = list(token[:-1]) + [token[-1] + '</w>']
        while len(pieces) > 1:
            pairs = [(ranks.get((pieces[i], pieces[i + 1]), 10**9), i) for i in range(len(pieces) - 1)]
            rank, index = min(pairs)
            if rank == 10**9:
                break
            pieces[index:index + 2] = [pieces[index] + pieces[index + 1]]
        result.extend(vocab[piece] for piece in pieces)
    result = result[:76] + [vocab['<|endoftext|>']]
    return result + [0] * (77 - len(result))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--precompute', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    checksums = {}
    required = FILES if args.precompute else {name: value for name, value in FILES.items() if '_image.' in name}
    legacy = OUT / 'mobileclip_s0.zip'
    if legacy.exists():
        with zipfile.ZipFile(legacy) as archive:
            for name in required:
                target = TEMP / name
                if not target.exists() and name in archive.namelist():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(name))
    for name, digest in required.items():
        print('Verifying', name, flush=True)
        checksums[name] = fetch(f'https://huggingface.co/apple/coreml-mobileclip/resolve/{REVISION}/{name}', TEMP / name, digest)
    if args.precompute:
        base = 'https://raw.githubusercontent.com/apple-aiml-research/ml-mobileclip/main/ios_app/MobileCLIPExplore/Resources/'
        fetch(base + 'clip-vocab.json', TEMP / 'clip-vocab.json')
        fetch(base + 'clip-merges.txt', TEMP / 'clip-merges.txt')
        prompts = {
            'recap': ['a television recap of previously shown scenes with subtitles', 'a previously on montage summarizing earlier episodes'],
            'opening': ['the opening title sequence of a television show with cast names', 'an opening theme song montage with a title logo'],
            'main': ['a scene from the main story with characters talking', 'a normal narrative scene from a movie or television episode'],
            'ending': ['closing credits with scrolling cast and crew names', 'the end credits of a television show on a dark background'],
        }
        vocab = json.loads((TEMP / 'clip-vocab.json').read_text('utf8'))
        merges = (TEMP / 'clip-merges.txt').read_text('utf8')
        prompt_bytes = json.dumps({k: [tokens(vocab, merges, p) for p in values] for k, values in prompts.items()}).encode('utf8')
        if (OUT / 'prompts.json').read_bytes() != prompt_bytes:
            raise ValueError('Anchor tokens changed; regenerate and review prompts explicitly')
        destination = args.output or (OUT / 'anchor_vectors.json')
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['swift', str(ROOT / 'tool/precompute_intro_vectors.swift'),
                        str(TEMP / 'mobileclip_s0_text.mlpackage'), str(OUT / 'prompts.json'),
                        REVISION, str(destination)], check=True)
        frozen = OUT / 'anchor_vectors.json'
        if frozen.exists():
            generated = json.loads(destination.read_text('utf8'))
            committed = json.loads(frozen.read_text('utf8'))
            for key in ['format', 'revision', 'promptsSha256', 'dimension']:
                if generated[key] != committed[key]:
                    raise ValueError('Frozen anchor metadata changed: ' + key)
            delta = max(abs(a - b) for label in generated['vectors']
                        for actual, expected in zip(generated['vectors'][label], committed['vectors'][label])
                        for a, b in zip(actual, expected))
            if delta > 1e-5:
                raise ValueError(f'Frozen anchors differ from model inference: {delta}')
            print(f'Frozen anchors match fresh Core ML inference (maximum delta {delta})', flush=True)
        print('Precomputed vectors:', destination, flush=True)
        return
    vectors = json.loads((OUT / 'anchor_vectors.json').read_text('utf8'))
    if vectors.get('format') != 'lumebox.intro.anchors.v1' or vectors.get('revision') != REVISION or vectors.get('promptsSha256') != hashlib.sha256((OUT / 'prompts.json').read_bytes()).hexdigest():
        raise ValueError('Anchor vectors do not match the pinned prompts/model')
    import math
    if vectors.get('dimension') != 512 or set(vectors['vectors']) != {'recap', 'opening', 'main', 'ending'} or any(
        len(examples) != 2 or any(len(vector) != 512 or not all(isinstance(value, (int, float)) and math.isfinite(value) for value in vector) or not any(vector) for vector in examples)
        for examples in vectors['vectors'].values()
    ):
        raise ValueError('Invalid anchor embedding dimensions or values')
    with zipfile.ZipFile(OUT / 'mobileclip_s0_image.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in required:
            archive.write(TEMP / name, name)
    checksums['yamnet.tflite'] = fetch('https://storage.googleapis.com/audioset/yamnet.tflite', OUT / 'yamnet.tflite', 'e193da5676a2fdb7a3702c10fba62aa27d76f64e4534467443811c1a2ff1667d')
    for name in ['anchor_vectors.json', 'mobileclip_s0_image.zip']:
        checksums[name] = hashlib.sha256((OUT / name).read_bytes()).hexdigest()
    for name in ['LICENSE', 'LICENSE_MODELS', 'ACKNOWLEDGEMENTS']:
        fetch('https://raw.githubusercontent.com/apple-aiml-research/ml-mobileclip/main/' + name, OUT / ('MobileCLIP-' + name + '.txt'))
    fetch('https://raw.githubusercontent.com/tensorflow/models/master/LICENSE', OUT / 'YAMNet-LICENSE.txt')
    (OUT / 'compact_checksums.json').write_text(json.dumps({'revision': REVISION, 'sha256': checksums}, indent=2), 'utf8')
    print('Models and prompt anchors ready.', flush=True)

if __name__ == '__main__':
    main()
