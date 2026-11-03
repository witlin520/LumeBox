"""Package a source directory for file/URL import; never executes its code."""
import argparse
import json
from pathlib import Path
import zipfile


def package_source(folder, output):
    folder = folder.resolve(strict=True)
    output = output.resolve()
    manifest = json.loads((folder / 'lume.json').read_text(encoding='utf-8'))
    entry = manifest['entry']
    candidate = folder / entry
    if not candidate.resolve().is_relative_to(folder) or not candidate.is_file():
        raise ValueError('lume.json entry 必须指向源包内文件')
    files = []
    total = 0
    for path in sorted(folder.rglob('*')):
        if path.is_symlink():
            raise ValueError('源包不能包含符号链接')
        if not path.is_file() or '__pycache__' in path.parts or path.suffix == '.pyc' or path == output:
            continue
        if path.suffix.lower() in ('.so', '.pyd', '.dylib', '.fwork', '.jar', '.dex', '.apk'):
            raise ValueError('原生扩展须随 App 构建签名，Android 代码需远程后端')
        total += path.stat().st_size
        files.append(path)
    if total > 8 * 1024 * 1024 or len(files) > 256:
        raise ValueError('源包不能超过 8MB / 256 个文件（wheel 展开后仍需满足此限制）')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.relative_to(folder).as_posix())
    print(output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package_source(args.folder, args.output)
