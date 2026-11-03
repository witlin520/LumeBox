"""Serve generated fixture with real byte ranges for Android media decoders."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1] / 'build/player-reference'
class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.serve(False)
    def do_GET(self):
        self.serve(True)
    def serve(self, body):
        if self.path not in ('/player-fixture.mp4', '/player-portrait-fixture.mp4'):
            self.send_error(404)
            return
        file = ROOT / self.path.lstrip('/')
        size = file.stat().st_size
        start, end = 0, size - 1
        match = re.fullmatch(r'bytes=(\d+)-(\d*)', self.headers.get('Range', ''))
        if match:
            start = int(match[1]); end = min(int(match[2]) if match[2] else size - 1, size - 1)
        if start > end or start >= size:
            self.send_error(416)
            return
        self.send_response(206 if match else 200)
        self.send_header('Content-Type', 'video/mp4')
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(end - start + 1))
        if match:
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers()
        if body:
            try:
                with file.open('rb') as stream:
                    stream.seek(start)
                    remaining = end - start + 1
                    while remaining:
                        chunk = stream.read(min(65536, remaining))
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass
if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
