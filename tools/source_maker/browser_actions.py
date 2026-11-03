import json
import re
import sys
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


def program(actions=None, selector='', purpose=''):
    root = Path(getattr(sys, '_MEIPASS', Path(__file__).parent))
    source = (root / 'page_actions.js').read_text(encoding='utf-8')
    return '(' + source + ')(' + json.dumps(actions or {}) + ',' + json.dumps(selector) + ',' + json.dumps(purpose) + ')'


def redact(value):
    if isinstance(value, dict):
        return {str(k): '[redacted]' if re.search(r'password|passwd|cookie|authorization|token|secret', str(k), re.I) else redact(v) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v) for v in value[:100]]
    return value


def network_row(url, status, body):
    parts = urlsplit(url)
    query = [(k, '[redacted]' if re.search(r'key|sign|token|secret|auth|pass', k, re.I) else v) for k, v in parse_qsl(parts.query)]
    return {'url': urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), '')), 'status': status, 'json': redact(body)}
