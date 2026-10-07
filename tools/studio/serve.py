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
WRITABLE = ("assets/", "data/cutscenes/", "data/dialogues/", "data/enemies/", "data/backdrops.json",
            "localization/strings.csv", "tools/studio/projects/", "tools/rooms/studio_rooms.json",
            "tools/studio/overrides/")
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


def image(req):
    """A picture for the studio with the key in this machine's environment (generate_image.py)."""
    import tempfile
    sys.path.insert(0, str(ROOT / "tools/studio"))
    import generate_image
    with tempfile.TemporaryDirectory() as tmp:
        refs = []
        for i, d in enumerate(req.pop("refs", [])):
            Path(tmp, f"ref{i}.png").write_bytes(base64.b64decode(d.split(",", 1)[1]))
            refs.append(f"ref{i}.png")
        path = Path(tmp, "request.json")
        path.write_text(json.dumps({**req, "refs": refs, "out": "out.png"}), encoding="utf-8")
        try:
            out = generate_image.generate(path)
        except SystemExit as e:
            return {"ok": False, "error": str(e)}
        return {"ok": True, "b64": base64.b64encode(out.read_bytes()).decode()}


def run(cmd, timeout=600):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout + r.stderr)[-6000:]


def dirty_files(paths):
    """Tracked files git sees as modified under these paths."""
    out = subprocess.run(["git", "status", "--porcelain", "--"] + paths, cwd=ROOT, capture_output=True, text=True).stdout
    return [line[3:] for line in out.splitlines() if line[:2] != "??"]


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
                regenerated = ""
                if "tools/rooms/studio_rooms.json" in written:
                    # what the studio's robot does on a pull request: the scenes follow the table.
                    # The panels it also re-encodes differ by a level here and there on other
                    # machines than CI's, so they are put back; only the scenes are meant to move.
                    code, regenerated = run([sys.executable, "tools/rooms/generate_rooms.py"])
                    run(["git", "checkout", "--", "assets/levels"])
                    if code != 0:
                        return self._json(200, {"ok": False, "error": "генератор комнат не принял изменения:\n" + regenerated[-3000:]})
                if any(w.startswith("tools/studio/overrides/") for w in written):
                    # her edit of a generated picture: the generators that own it lay it over their own
                    # picture (what the studio's robot does on a pull request). What else they rewrite
                    # here differs by a level from CI's machine, so only the overridden pictures keep
                    # the regeneration; everything else is put back as it was a moment ago — including
                    # anything of hers not committed yet.
                    owned = ["assets", "scenes/rooms", "data/enemy_archetypes"]
                    before = {rel: (ROOT / rel).read_bytes() for rel in dirty_files(owned) if (ROOT / rel).is_file()}
                    code, out = run([sys.executable, "tools/art/studio_overrides.py", "regenerate"])
                    if code != 0:
                        return self._json(200, {"ok": False, "error": "генератор не принял правку:\n" + out[-3000:]})
                    keep = set(json.loads((ROOT / "tools/studio/overrides/overrides.json").read_text(encoding="utf-8")))
                    for rel in dirty_files(owned):
                        if rel in keep:
                            continue
                        if rel in before:
                            (ROOT / rel).write_bytes(before[rel])
                        else:
                            run(["git", "checkout", "--", rel])
                # the page reads the game through import/: rebuild it, or it would show the old version
                subprocess.run([sys.executable, str(ROOT / "tools/studio/build_data.py")], cwd=ROOT, capture_output=True)
                return self._json(200, {"ok": True, "written": written, "deleted": removed, "regenerated": bool(regenerated)})
            if self.path == "/api/image":
                return self._json(200, image(data))
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
