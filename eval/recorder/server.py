#!/usr/bin/env python3
"""Minimal recorder server. stdlib only, no cgi (removed in 3.13+).

Protocol for /save:
  POST /save
    Header: X-Meta  = URL-encoded JSON ({id, lang, bucket, scene, text, sample_rate, duration})
    Body              = raw WAV bytes
  -> writes recordings/<id>.wav and appends manifest.jsonl

Usage:
  python3 server.py [port]
"""
import json
import os
import sys
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

ROOT = Path(__file__).parent.resolve()
REC_DIR = ROOT / "recordings"
REC_DIR.mkdir(exist_ok=True)
MANIFEST = REC_DIR / "manifest.jsonl"

STATIC = {
    "/": "index.html",
    "/index.html": "index.html",
    "/scripts.json": "scripts.json",
    "/recorder-worklet.js": "recorder-worklet.js",
}

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".wav": "audio/wav",
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")

    def _serve_file(self, path: Path):
        if not path.is_file():
            self.send_error(404)
            return
        mime = MIME.get(path.suffix, "application/octet-stream")
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _send_json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in STATIC:
            self._serve_file(ROOT / STATIC[path])
            return
        if path == "/status":
            ids = sorted(p.stem for p in REC_DIR.glob("*.wav"))
            self._send_json({"recorded": ids})
            return
        if path.startswith("/recordings/"):
            name = path[len("/recordings/"):]
            if "/" in name or ".." in name:
                self.send_error(400)
                return
            self._serve_file(REC_DIR / name)
            return
        self.send_error(404)

    def do_POST(self):
        if self.path != "/save":
            self.send_error(404)
            return
        meta_header = self.headers.get("X-Meta")
        if not meta_header:
            self.send_error(400, "missing X-Meta header")
            return
        try:
            meta = json.loads(urllib.parse.unquote(meta_header))
        except json.JSONDecodeError:
            self.send_error(400, "bad X-Meta json")
            return
        rid = str(meta.get("id") or "")
        if not rid or not rid.isalnum():
            self.send_error(400, "bad id")
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            self.send_error(400, "empty body")
            return
        wav_bytes = self.rfile.read(length)
        (REC_DIR / f"{rid}.wav").write_bytes(wav_bytes)
        with MANIFEST.open("a", encoding="utf-8") as f:
            f.write(json.dumps({**meta, "bytes": len(wav_bytes)}, ensure_ascii=False) + "\n")
        self._send_json({"ok": True, "id": rid, "bytes": len(wav_bytes)})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    os.chdir(ROOT)
    httpd = HTTPServer(("127.0.0.1", port), Handler)
    print(f"\n  Voice Dictation Recorder")
    print(f"  http://127.0.0.1:{port}")
    print(f"  recordings -> {REC_DIR}")
    print(f"  Ctrl+C to stop\n")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
