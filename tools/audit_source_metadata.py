"""Audit local source declarations without executing source scripts or fetching feeds.

Usage: python tools/audit_source_metadata.py REPOSITORY OUTPUT_JSON
Missing declarations are evidence for review, not proof of a broken image.
Unknown ratings are deliberately never inferred from missing metadata.
"""
import argparse
import json
import pathlib
import re


def audit(root):
    catalog = json.loads((root / 'metadata/content-ratings.json' if (root / 'metadata/content-ratings.json').exists() else root / 'content-ratings.json').read_text(encoding='utf-8'))
    ratings = catalog.get('sources', {})
    rows = []
    manifests = []
    for section in ('comic', 'photo', 'video', 'movie', 'audiobook'):
        for path in sorted((root / section).glob('*.js')):
            text = path.read_text(encoding='utf-8-sig')
            match = re.search(r'^\s*//\s*@?LumeSource\s*[:=]\s*(\{[^\n]+\})', text, re.M)
            if not match:
                manifests.append(path.relative_to(root).as_posix())
                continue
            try:
                meta = json.loads(match[1])
            except ValueError:
                rows.append({'file': path.relative_to(root).as_posix(), 'error': 'invalid metadata JSON'})
                continue
            mirrors = meta.get('mirrors') or []
            host = re.search(r'''\b(?:BASE_URL|BASE|HOST|baseURL|baseUrl|base_url|base|host|H\.base)\s*[:=]\s*['"](https?://[^'"]+)''', text)
            host_list = re.search(r'''HOSTS\s*=\s*\[\s*['"](https?://[^'"]+)''', text)
            declared_rating = ratings.get(meta.get('id'), {}).get('rating', 'unknown')
            rows.append({
                'file': path.relative_to(root).as_posix(),
                'id': meta.get('id'), 'name': meta.get('name'),
                'rating': declared_rating,
                'iconDeclared': bool(meta.get('icon') or meta.get('iconUrl')),
                'siteRecognizable': bool(host or host_list or mirrors),
                'coverHeadersDeclared': 'coverHeaders' in text,
                'coverValidation': 'requires runtime validation; declarations alone do not prove availability',
            })
    return {
        'scope': 'static metadata only; no source execution or media download',
        'summary': {
            'sources': len(rows), 'nonSourceFiles': len(manifests),
            'adult': sum(row.get('rating') == '18+' for row in rows),
            'unclassified': sum(row.get('rating') == 'unknown' for row in rows),
            'missingExplicitIcon': sum(not row.get('iconDeclared') for row in rows),
            'missingRecognizableSite': sum(not row.get('siteRecognizable') for row in rows),
        },
        'nonSourceFiles': manifests,
        'sources': rows,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', type=pathlib.Path)
    parser.add_argument('output', type=pathlib.Path)
    args = parser.parse_args()
    result = audit(args.repository)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result['summary']))
