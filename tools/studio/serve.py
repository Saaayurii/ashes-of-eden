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
import threading
from contextlib import contextmanager
from io import BytesIO
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRITABLE = ("assets/", "data/", "data/cutscenes/", "data/dialogues/", "data/enemies/", "data/abilities/", "data/projectiles.json", "data/action_fx.json", "data/enemy_archetypes/tree.json", "data/backdrops.json",
            "localization/strings.csv", "tools/studio/projects/", "tools/rooms/studio_rooms.json",
            "tools/studio/overrides/")
WRITE_LOCK = threading.RLock()
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


def prepared_changes(files, delete):
    targets = []
    for f in files:
        path = safe_path(f["path"])
        raw = base64.b64decode(f["b64"], validate=True)
        if path.suffix == ".json":
            json.loads(raw.decode("utf-8"), parse_constant=lambda v: (_ for _ in ()).throw(ValueError(f"invalid number: {v}")))
        if path.suffix.lower() == ".png":
            from PIL import Image
            Image.open(BytesIO(raw)).verify()
        targets.append((path, raw))
    doomed = [safe_path(p) for p in delete]
    paths = [p for p, _ in targets]
    if len(set(paths)) != len(paths) or set(paths) & set(doomed):
        raise ValueError("duplicate write or simultaneous write/delete")
    return targets, doomed


def apply_changes(files, delete):
    targets, doomed = prepared_changes(files, delete)
    written, removed = [], []
    all_paths = [p for p, _ in targets] + [q for p in doomed for q in (p, p.with_name(p.name + ".import"))]
    before = {p: p.read_bytes() if p.is_file() else None for p in all_paths}
    try:
        for path, raw in targets:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            written.append(path.relative_to(ROOT).as_posix())
        for path in doomed:
            for p in (path, path.with_name(path.name + ".import")):
                if p.exists():
                    p.unlink()
                    removed.append(p.relative_to(ROOT).as_posix())
    except Exception:
        restore_files(before)
        raise
    return written, removed


def restore_files(before):
    for path, raw in before.items():
        if raw is None:
            if path.is_file():
                path.unlink()
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)


def snapshot_tree(dirs):
    return {p: p.read_bytes() for d in dirs for p in (ROOT / d).rglob("*") if p.is_file()}


@contextmanager
def write_transaction(files, delete):
    # Serialize writes, validate *all* submitted bytes first, and include generator
    # outputs in the rollback. Never discard the user's unrelated working changes.
    with WRITE_LOCK:
        targets, doomed = prepared_changes(files, delete)
        dirs = ["data", "localization", "tools/studio/overrides", "tools/studio/import", "tools/studio/projects", "tools/rooms"]
        if any(f["path"].startswith("tools/studio/overrides/") or f["path"] == "tools/rooms/studio_rooms.json" for f in files):
            dirs += [p.relative_to(ROOT).as_posix() for p in (ROOT / "assets").iterdir() if p.is_dir() and p.name != "audio"] + ["scenes/rooms"]
        direct = [p for p, _ in targets] + [q for p in doomed for q in (p, p.with_name(p.name + ".import"))]
        before = snapshot_tree(dirs)
        before.update({p: p.read_bytes() if p.is_file() else None for p in direct})
        try:
            yield before
        except Exception:
            after = snapshot_tree(dirs)
            after.update({p: None for p in direct})
            restore_files({p: before.get(p) for p in after.keys() | before.keys()})
            raise


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
                with write_transaction(data.get("files", []), data.get("delete", [])) as before:
                    written, removed = apply_changes(data.get("files", []), data.get("delete", []))
                    regenerated = False
                    if "tools/rooms/studio_rooms.json" in written:
                        code, out = run([sys.executable, "tools/rooms/generate_rooms.py"])
                        if code:
                            raise ValueError("генератор комнат не принял изменения:\n" + out)
                        regenerated = True
                        # Room generation owns scenes, not the already-painted panels.
                        restore_files({p: raw for p, raw in before.items() if "assets/levels/" in p.relative_to(ROOT).as_posix()})
                    if any(w.startswith("tools/studio/overrides/") for w in written):
                        manifest = ROOT / "tools/studio/overrides/overrides.json"
                        old = json.loads(before.get(manifest, b"{}"))
                        new = json.loads(manifest.read_text(encoding="utf-8"))
                        keep = {rel for rel, entry in new.items() if old.get(rel) != entry}
                        for rel in new:
                            edit = "tools/studio/overrides/" + rel
                            mask = edit[:-4] + ".mask.png"
                            if edit in written or mask in written:
                                keep.add(rel)
                        code, out = run([sys.executable, "tools/art/studio_overrides.py", "regenerate"])
                        if code:
                            raise ValueError("генератор не принял правку:\n" + out)
                        owned = snapshot_tree([p.relative_to(ROOT).as_posix() for p in (ROOT / "assets").iterdir() if p.is_dir() and p.name != "audio"] + ["scenes/rooms", "data/enemy_archetypes"])
                        explicit = set(written)
                        for p in owned.keys() | before.keys():
                            rel = p.relative_to(ROOT).as_posix()
                            if not rel.startswith(("assets/", "scenes/rooms/", "data/enemy_archetypes/")):
                                continue
                            if rel not in keep and rel not in explicit:
                                restore_files({p: before.get(p)})
                    code, out = run([sys.executable, "tools/studio/build_data.py"])
                    if code:
                        raise ValueError("не удалось обновить данные студии:\n" + out)
                    g = godot()
                    if g:
                        code, out = run([g, "--headless", "--path", str(ROOT), "-s", "scripts/tools/validate_data.gd"])
                        if code:
                            raise ValueError("проверка данных не пройдена; изменения отменены:\n" + out)
                return self._json(200, {"ok": True, "written": written, "deleted": removed, "regenerated": regenerated})
            if self.path == "/api/image":
                return self._json(200, image(data))
            g = godot()
            if self.path in ("/api/validate", "/api/run") and not g:
                return self._json(500, {"ok": False, "error": "Godot not found: set GODOT=/path/to/godot"})
            if self.path == "/api/validate":
                with WRITE_LOCK:
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
            print(str(e), file=sys.stderr, flush=True)
            return self._json(400, {"ok": False, "error": str(e)})
        except Exception as e:  # report it to the page rather than hang the request
            return self._json(500, {"ok": False, "error": f"{type(e).__name__}: {e}"})


class Server(ThreadingHTTPServer):
    # The page asks for the game's rooms all at once (rooms_list.json, then 25
    # files and their pictures) while the browser still holds other loads open.
    # With socketserver's backlog of 5 the extra connections were reset: the
    # import failed with "Failed to fetch" and the backgrounds tab stayed empty.
    request_queue_size = 128
    daemon_threads = True


def main():
    if not (ROOT / "tools/studio/import/meta.json").exists():
        print("building the studio's data first (tools/studio/build_data.py)…")
        subprocess.run([sys.executable, str(ROOT / "tools/studio/build_data.py")], check=True)
    print(f"Studio: http://localhost:{PORT}/tools/studio/  (writes into {ROOT})")
    Server(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
