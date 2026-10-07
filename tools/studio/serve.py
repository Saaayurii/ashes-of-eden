#!/usr/bin/env python3
"""Serves the art studio from this repository and lets it write into it.

    python3 tools/studio/serve.py          # then open http://localhost:8765/tools/studio/

The page is the same one GitHub Pages hosts; served from here it finds this
small API and, instead of opening a pull request, writes straight into the
working tree, runs the data validator and opens Godot in a room:

    GET  /api/ping                      {"ok": true, "branch": ..., "godot": ...}
    POST /api/write   {"files": [{"path", "b64"}], "delete": [path]}
    POST /api/validate                  scripts/tools/validate_data.gd, headless
    POST /api/run     {"room": name}    make room ROOM=name, without make

It binds to 127.0.0.1 only and writes only under WRITABLE: the studio's
outputs never touch scripts, scenes or the tools themselves.
"""
import base64
import json
import os
import shutil
import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRITABLE = ("assets/", "data/cutscenes/", "data/dialogues/", "data/backdrops.json",
            "localization/strings.csv", "tools/studio/projects/")
PORT = int(os.environ.get("STUDIO_PORT", "8765"))


def godot():
    for candidate in (os.environ.get("GODOT"), "/Applications/Godot.app/Contents/MacOS/Godot",
                      shutil.which("godot"), shutil.which("godot4")):
        if candidate and Path(candidate).exists():
            return candidate
    return None


def safe_path(rel: str) -> Path:
    """The repository file a studio path names, or ValueError if it may not be written."""
    rel = rel.replace("\\", "/").lstrip("/")
    path = (ROOT / rel).resolve()
    if ROOT not in path.parents or not any(rel == w or rel.startswith(w) for w in WRITABLE) or ".." in rel.split("/"):
        raise ValueError(f"not writable from the studio: {rel}")
    return path


def apply_changes(files, delete):
    written, removed = [], []
    targets = [(safe_path(f["path"]), f) for f in files]  # check everything before touching anything
    doomed = [safe_path(p) for p in delete]
    for path, f in targets:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(base64.b64decode(f["b64"]))
        written.append(path.relative_to(ROOT).as_posix())
    for path in doomed:
        for p in (path, path.with_name(path.name + ".import")):
            if p.exists():
                p.unlink()
                removed.append(p.relative_to(ROOT).as_posix())
    return written, removed


def run(cmd, timeout=600):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout + r.stderr)[-6000:]


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(ROOT), **kw)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")  # the page and the data change under it
        super().end_headers()

    def _json(self, code, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/ping":
            branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"])[1].strip()
            return self._json(200, {"ok": True, "branch": branch, "godot": godot()})
        return super().do_GET()

    def do_POST(self):
        try:
            data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            if self.path == "/api/write":
                written, removed = apply_changes(data.get("files", []), data.get("delete", []))
                # the page reads the game through import/: rebuild it, or it would show the old version
                subprocess.run([sys.executable, str(ROOT / "tools/studio/build_data.py")], cwd=ROOT, capture_output=True)
                return self._json(200, {"ok": True, "written": written, "deleted": removed})
            g = godot()
            if self.path in ("/api/validate", "/api/run") and not g:
                return self._json(500, {"ok": False, "error": "Godot not found: set GODOT=/path/to/godot"})
            if self.path == "/api/validate":
                code, out = run([g, "--headless", "--path", str(ROOT), "--import"])
                if code == 0:
                    code, out = run([g, "--headless", "--path", str(ROOT), "-s", "scripts/tools/validate_data.gd"])
                return self._json(200, {"ok": code == 0, "log": out})
            if self.path == "/api/run":
                room = str(data.get("room", ""))
                if not room.replace("_", "").isalnum():
                    raise ValueError("bad room name")
                run([g, "--headless", "--path", str(ROOT), "--import"])
                subprocess.Popen([g, "--path", str(ROOT), "scenes/run/run.tscn", "--", f"room={room}"], cwd=ROOT)
                return self._json(200, {"ok": True})
            return self._json(404, {"ok": False, "error": "no such endpoint"})
        except ValueError as e:
            return self._json(400, {"ok": False, "error": str(e)})
        except Exception as e:  # report it to the page rather than hang the request
            return self._json(500, {"ok": False, "error": f"{type(e).__name__}: {e}"})


def main():
    if not (ROOT / "tools/studio/import/meta.json").exists():
        print("building the studio's data first (tools/studio/build_data.py)…")
        subprocess.run([sys.executable, str(ROOT / "tools/studio/build_data.py")], check=True)
    print(f"Studio: http://localhost:{PORT}/tools/studio/  (writes into {ROOT})")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
