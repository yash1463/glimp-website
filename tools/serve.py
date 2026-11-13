"""Local preview: python tools/serve.py  →  http://localhost:8765  (threaded, correct WebP type)."""
import functools, http.server, mimetypes, os
mimetypes.add_type("image/webp", ".webp")
mimetypes.add_type("application/javascript", ".js")
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
Handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
Handler.func.extensions_map[".webp"] = "image/webp"
http.server.ThreadingHTTPServer(("", 8765), Handler).serve_forever()
