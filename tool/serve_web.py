"""Sert build/web en local pour tester la version web (http://localhost:8765).

Usage : python tool/serve_web.py
(après `flutter build web --release`)
"""
import functools
import http.server
import os

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'build', 'web')

Handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=ROOT)
http.server.SimpleHTTPRequestHandler.extensions_map.update({
    '.wasm': 'application/wasm',
    '.mjs': 'text/javascript',
    '.js': 'text/javascript',
})

if __name__ == '__main__':
    http.server.ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
