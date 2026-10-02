"""Serve the Flutter web build for previewing. Uses $PORT when set (default 3300)."""
import functools
import http.server
import os
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent / "build" / "web"
port = int(os.environ.get("PORT", "3300"))
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
print(f"Serving {root} on http://localhost:{port}", flush=True)
http.server.ThreadingHTTPServer(("", port), handler).serve_forever()
