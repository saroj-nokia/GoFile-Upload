#!/usr/bin/env python3
"""Tiny fake GoFile API for test/run.sh (no network, nothing is stored).

Usage: mock_gofile.py PORT LOGFILE

GET  /servers   -> two fake servers
GET  /reset     -> resets the /flaky counter
POST /<mode>    -> the upload endpoint; the path picks the behaviour:
    ok        success (with guestToken, parentFolder and the real MD5)
    badmd5    success, but with a wrong MD5
    nofolder  success, but without parentFolder / guestToken
    fail      HTTP 500 JSON error
    bad4      HTTP 401 JSON error (bad token)
    html      HTTP 502 with an HTML body
    flaky     HTTP 500 on the first request after /reset, then success
    slow      success after 3 s (for the SIGTERM test)
Every POST is appended to LOGFILE as one JSON line.
"""
import hashlib
import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, LOG = int(sys.argv[1]), sys.argv[2]
state = {"flaky_hits": 0}


def parse_multipart(content_type, body):
    boundary = re.search(r"boundary=(.+)", content_type).group(1).encode()
    fields = {}
    for chunk in body.split(b"--" + boundary)[1:-1]:
        head, _, data = chunk.partition(b"\r\n\r\n")
        if data.endswith(b"\r\n"):
            data = data[:-2]
        name = re.search(rb'name="([^"]+)"', head).group(1).decode()
        fname = re.search(rb'filename="([^"]*)"', head)
        fields[name] = (fname.group(1).decode() if fname else None, data)
    return fields


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        raw = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == "/servers":
            self._send(200, {"status": "ok", "data": {"servers": [{"name": "s1"}, {"name": "s2"}]}})
        else:
            if self.path == "/reset":
                state["flaky_hits"] = 0
            self._send(200, {"status": "ok"})

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        fields = parse_multipart(self.headers.get("Content-Type", ""), body)
        fname, content = fields.get("file", (None, b""))
        field = lambda k: fields[k][1].decode() if k in fields else None
        with open(LOG, "a") as log:
            log.write(json.dumps({
                "path": self.path,
                "auth": self.headers.get("Authorization", ""),
                "token": field("token"),
                "folderId": field("folderId"),
                "filename": fname,
            }) + "\n")

        mode = self.path.lstrip("/")
        if mode == "fail":
            return self._send(500, {"status": "error-internal", "message": "internal boom"})
        if mode == "bad4":
            return self._send(401, {"status": "error-auth", "message": "invalid token"})
        if mode == "html":
            return self._send(502, b"<html>Bad Gateway</html>", "text/html")
        if mode == "flaky":
            state["flaky_hits"] += 1
            if state["flaky_hits"] == 1:
                return self._send(500, {"status": "error-internal", "message": "try again"})
        if mode == "slow":
            time.sleep(3)

        data = {"downloadPage": "https://gofile.io/d/abc123", "code": "abc123",
                "fileName": fname, "md5": hashlib.md5(content).hexdigest()}
        if mode != "nofolder":
            data["parentFolder"] = "pf1"
            data["guestToken"] = "gtok"
        if mode == "badmd5":
            data["md5"] = "0" * 32
        self._send(200, {"status": "ok", "data": data})

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
