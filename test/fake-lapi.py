"""Minimal CrowdSec LAPI for the smoke test: one IPv4 and one IPv6 ban.

Usage: python3 -I test/fake-lapi.py <port> <api key>
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, KEY = int(sys.argv[1]), sys.argv[2]
BANS = [
    {"id": 1, "origin": "cscli", "scenario": "smoke", "scope": "Ip",
     "type": "ban", "value": "192.0.2.1", "duration": "1h"},
    {"id": 2, "origin": "cscli", "scenario": "smoke", "scope": "Ip",
     "type": "ban", "value": "2001:db8::1", "duration": "1h"},
]


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.headers.get("X-Api-Key") != KEY:
            return self.reply(403, {"message": "access forbidden"})
        if self.path.startswith("/v1/decisions/stream"):
            new = BANS if "startup=true" in self.path else []
            return self.reply(200, {"new": new, "deleted": []})
        self.reply(404, {"message": "not found"})

    def do_POST(self):
        # usage metrics
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self.reply(201, {})

    def log_message(self, fmt, *args):
        sys.stderr.write("fake-lapi: " + fmt % args + "\n")


ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
