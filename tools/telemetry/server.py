#!/usr/bin/env python3
"""The receiver for the game's opt-in telemetry (scripts/autoload/telemetry.gd).

Standard library only. POST /collect with {"format": 1, "records": [...]} appends
each record, stamped with the day it arrived, as one line of
<data>/records-YYYY-MM.jsonl. Nothing about the sender is kept — not the
address, not the user agent: the rate limit holds addresses in memory only.

    python3 tools/telemetry/server.py --port 8930 --data build/telemetry
    TELEMETRY_TOKEN=secret python3 tools/telemetry/server.py   # GET /export needs it

Endpoints:
    POST /collect   records in (text/plain or application/json; CORS open,
                    so the Web build on any origin can send)
    OPTIONS *       the CORS preflight
    GET  /health    "ok"
    GET  /export    every record, JSONL, with "Authorization: Bearer <token>"
                    (off when TELEMETRY_TOKEN is unset); tools/telemetry/pull.py

Limits: a body over MAX_BODY, more than BATCH_MAX records, a record over
MAX_RECORD or without an id is refused; an address may post RATE_COUNT times
per RATE_WINDOW seconds. The game keeps what was refused and tries later, so a
refusal costs nothing but time. Put it behind Caddy or nginx for https (a page
served over https may only send to https; docs/PLAYTEST.md).
"""

from __future__ import annotations

import argparse
import datetime as dt
import hmac
import json
import os
import pathlib
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BODY = 512 * 1024
MAX_RECORD = 128 * 1024
BATCH_MAX = 20
RATE_COUNT = 30
RATE_WINDOW = 60.0
FORMATS = {1}


class Store:
    """Appends records to a month's file, one writer at a time."""

    def __init__(self, folder: pathlib.Path):
        self.folder = folder
        self.folder.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()

    def append(self, records: list[dict]) -> None:
        now = dt.datetime.now(dt.timezone.utc)
        path = self.folder / f"records-{now:%Y-%m}.jsonl"
        lines = []
        for record in records:
            record = dict(record)
            record["received"] = now.strftime("%Y-%m-%d")
            lines.append(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
        with self.lock, open(path, "a", encoding="utf-8") as out:
            out.writelines(lines)

    def export(self) -> bytes:
        parts = []
        for path in sorted(self.folder.glob("records-*.jsonl")):
            parts.append(path.read_bytes())
        return b"".join(parts)


class RateLimit:
    """At most `count` posts per `window` seconds per address, in memory only."""

    def __init__(self, count: int = RATE_COUNT, window: float = RATE_WINDOW):
        self.count = count
        self.window = window
        self.hits: dict[str, list[float]] = {}
        self.lock = threading.Lock()

    def allow(self, key: str, now: float | None = None) -> bool:
        now = time.monotonic() if now is None else now
        with self.lock:
            if len(self.hits) > 10000:  # forget the idle ones rather than grow
                self.hits = {k: v for k, v in self.hits.items() if v and now - v[-1] < self.window}
            recent = [t for t in self.hits.get(key, []) if now - t < self.window]
            if len(recent) >= self.count:
                self.hits[key] = recent
                return False
            recent.append(now)
            self.hits[key] = recent
            return True


def validate(payload) -> list[dict] | str:
    """The records of a batch, or why it is refused."""
    if not isinstance(payload, dict):
        return "not an object"
    if payload.get("format") not in FORMATS:
        return "unknown format"
    records = payload.get("records")
    if not isinstance(records, list) or not records:
        return "no records"
    if len(records) > BATCH_MAX:
        return "too many records"
    clean = []
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("id"), str) or not record["id"]:
            return "a record without an id"
        if len(json.dumps(record)) > MAX_RECORD:
            return "a record too large"
        clean.append(record)
    return clean


def make_handler(store: Store, limit: RateLimit, token: str, trust_proxy: bool):
    class Handler(BaseHTTPRequestHandler):
        server_version = "AshesTelemetry/1"
        sys_version = ""

        def log_message(self, fmt, *args):  # no addresses in the logs either
            pass

        def _cors(self) -> None:
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
            self.send_header("Access-Control-Max-Age", "86400")
            # a cross-origin-isolated page (COEP) may still read the answer
            self.send_header("Cross-Origin-Resource-Policy", "cross-origin")

        def _reply(self, code: int, body: bytes = b"", kind: str = "text/plain; charset=utf-8") -> None:
            self.send_response(code)
            self._cors()
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if body and self.command != "HEAD":
                self.wfile.write(body)

        def _sender(self) -> str:
            if trust_proxy:
                forwarded = self.headers.get("X-Forwarded-For", "")
                if forwarded:
                    return forwarded.split(",")[0].strip()
            return self.client_address[0]

        def do_OPTIONS(self):
            self._reply(204)

        def do_GET(self):
            path = self.path.split("?")[0]
            if path == "/health":
                self._reply(200, b"ok")
            elif path == "/export":
                given = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
                if not token or not hmac.compare_digest(given, token):
                    self._reply(403, b"forbidden")
                else:
                    self._reply(200, store.export(), "application/x-ndjson")
            else:
                self._reply(404, b"not found")

        def do_POST(self):
            if self.path.split("?")[0] not in ("/collect", "/"):
                self._reply(404, b"not found")
                return
            if not limit.allow(self._sender()):
                self._reply(429, b"slow down")
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = -1
            if length <= 0 or length > MAX_BODY:
                self._reply(413 if length > MAX_BODY else 400, b"bad length")
                return
            try:
                payload = json.loads(self.rfile.read(length).decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                self._reply(400, b"not json")
                return
            records = validate(payload)
            if isinstance(records, str):
                self._reply(400, records.encode())
                return
            store.append(records)
            self._reply(200, b'{"ok":true}', "application/json")

    return Handler


def serve(port: int, data: pathlib.Path, host: str = "0.0.0.0", token: str = "",
          trust_proxy: bool = False) -> ThreadingHTTPServer:
    handler = make_handler(Store(data), RateLimit(), token, trust_proxy)
    return ThreadingHTTPServer((host, port), handler)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8930")))
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--data", default=os.environ.get("TELEMETRY_DATA", "build/telemetry"))
    parser.add_argument("--trust-proxy", action="store_true",
                        help="rate-limit by X-Forwarded-For (only behind your own proxy)")
    args = parser.parse_args()
    httpd = serve(args.port, pathlib.Path(args.data), args.host,
                  os.environ.get("TELEMETRY_TOKEN", ""), args.trust_proxy)
    print(f"telemetry: http://{args.host}:{args.port}/collect -> {args.data}", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
