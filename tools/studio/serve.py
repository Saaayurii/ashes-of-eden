#!/usr/bin/env python3
"""Serves the art studio from this repository and lets it write into it.

    python3 tools/studio/serve.py          # then open http://localhost:8765/tools/studio/
    python3 tools/studio/serve.py --game ../saints-of-rust   # another game on this engine

With --game the pack is laid over the engine as content/ (tools/packs/apply_pack.py,
a link, so its repository is what changes) and the studio edits that game: a
file it writes goes into the pack — data/hero.json becomes the pack's own
data/hero.json, which overrides the engine's (docs/GAME_PACKS.md).

The page is the same one GitHub Pages hosts; served from here it finds this
small API and, instead of opening a pull request, writes straight into the
working tree, runs the data validator and opens Godot in a room:

    GET  /api/ping                      {"ok": true, "branch": ..., "godot": ...}
    POST /api/write   {"files": [{"path", "b64"}], "delete": [path]}
    POST /api/validate                  scripts/tools/validate_data.gd, headless
    POST /api/run     {"room": name}    make room ROOM=name, without make
                      {"composed": true}  ... its composed draft (tools/rooms/compose.py)
    POST /api/check   {"room": name}    the engine's reach, stairs and void-fall tests on its draft

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
import time
from contextlib import contextmanager
from io import BytesIO
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRITABLE = ("assets/", "data/", "data/cutscenes/", "data/dialogues/", "data/enemies/", "data/abilities/", "data/projectiles.json", "data/action_fx.json", "data/enemy_archetypes/tree.json", "data/backdrops.json",
            "localization/strings.csv", "tools/audio/music_manifest.json", "tools/studio/projects/", "tools/rooms/studio_rooms.json", "tools/rooms/composed_rooms.json",
            "tools/rooms/front_layers.json", "tools/studio/overrides/")
## Tables the rooms generator reads: writing one regenerates the rooms.
ROOM_TABLES = ("tools/rooms/studio_rooms.json", "tools/rooms/composed_rooms.json", "tools/rooms/front_layers.json")
## A game pack's own (content/…, generate_rooms.py --pack); the studio writes the last two.
PACK_TABLES = ("content/rooms/rooms.json", "content/rooms/composed_rooms.json", "content/rooms/studio_rooms.json")
## What the generator writes into assets/levels that a send means to change: a composed room's
## picture and plate, the pieces in front of the hero and what they were cut from. The panels it
## re-saves there otherwise only drift by a pixel on another zlib.
COMPOSED_OUT = ("assets/levels/composed/", "assets/levels/panels/", "assets/levels/front/", "assets/levels/pieces/")
## The engine's own checks of a composed draft (`/api/check`): the bot walks it, every stair both
## ways, every open column of its bottom edge is a fall out of the map.
CHECKS = (("reach_test", ["--fixed-fps", "60"], ["{room}", "--composed"]),
          ("stairs_test", ["--fixed-fps", "60"], ["--composed", "{room}"]),
          ("void_fall_test", ["--fixed-fps", "60"], ["--composed", "{room}"]))
WRITE_LOCK = threading.RLock()
PACK: Path | None = None  # --game: the pack's folder, linked in as content/
PORT = int(os.environ.get("STUDIO_PORT", "8765"))


def godot():
    for candidate in (os.environ.get("GODOT"), "/Applications/Godot.app/Contents/MacOS/Godot",
                      shutil.which("godot"), shutil.which("godot4")):
        if candidate and Path(candidate).exists():
            return candidate
    return None


def safe_path(rel: str) -> Path:
    """The repository file a studio path names, or ValueError if it may not be written.
    With --game, content/<path> is the pack's file and the same rules hold inside it."""
    rel = rel.replace("\\", "/").lstrip("/")
    base, inner = ROOT, rel
    if PACK is not None and rel.startswith("content/"):
        base, inner = PACK, rel.removeprefix("content/")
    path = (base / inner).resolve()
    writable = WRITABLE + (tuple(t.removeprefix("content/") for t in PACK_TABLES) if base == PACK else ())
    if base not in path.parents or not any(inner == w or inner.startswith(w) for w in writable) or ".." in rel.split("/"):
        raise ValueError(f"not writable from the studio: {rel}")
    return path


def rel_of(path: Path) -> str:
    """A written file as the page names it: content/… for the pack's."""
    if PACK is not None and PACK in path.parents:
        return "content/" + path.relative_to(PACK).as_posix()
    return path.relative_to(ROOT).as_posix()


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
            written.append(rel_of(path))
        for path in doomed:
            for p in (path, path.with_name(path.name + ".import")):
                if p.exists():
                    p.unlink()
                    removed.append(rel_of(p))
    except Exception:
        restore_files(before)
        raise
    return written, removed


def restore_files(before):
    # Touch only what changed: a rollback that rewrites every snapshotted file
    # fails on one it may read but not write (CI's .import files belong to the
    # Docker image's root) and hides the error that caused it.
    for path, raw in before.items():
        if raw is None:
            if path.is_file():
                path.unlink()
        elif not path.is_file() or path.read_bytes() != raw:
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
        if PACK is not None:
            dirs += ["content/data", "content/localization", "content/rooms", "content/scenes/rooms", "content/assets/levels"]
        if any(f["path"].startswith("tools/studio/overrides/") or f["path"] in ROOM_TABLES for f in files):
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


def changed_rooms(before, written):
    """The rooms whose entries a write changed in the room tables (each is keyed by room): only
    those are regenerated — the rest are what their tables already wrote, as CI holds them
    (tools/check_generators.py). None when a table did not parse before: then every room."""
    rooms = set()
    for table in ROOM_TABLES:
        if table not in written:
            continue
        path = ROOT / table
        try:
            old = json.loads(before.get(path) or b"{}")
        except ValueError:
            return None
        new = json.loads(path.read_text(encoding="utf-8"))
        rooms |= {name for name in old.keys() | new.keys() if old.get(name) != new.get(name)}
    return sorted(rooms)


def run(cmd, timeout=600):
    t = time.monotonic()
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if cmd[0] == sys.executable:  # where a write's seconds went, in the server's log
        print(f"  {' '.join(cmd[1:])}: {time.monotonic() - t:.1f} s", file=sys.stderr, flush=True)
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
            game = {}
            if PACK is not None:
                game = json.loads((PACK / "data/game.json").read_text(encoding="utf-8"))
                game = {"id": game.get("id", ""), "name": game.get("name", ""), "path": str(PACK)}
            return self._json(200, {"ok": True, "branch": branch, "godot": godot(), "game": game})
        return super().do_GET()

    def do_POST(self):
        try:
            data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            if self.path == "/api/write":
                with write_transaction(data.get("files", []), data.get("delete", [])) as before:
                    written, removed = apply_changes(data.get("files", []), data.get("delete", []))
                    regenerated = False
                    if PACK is not None and any(t in written for t in PACK_TABLES):
                        code, out = run([sys.executable, "tools/rooms/generate_rooms.py", "--pack"])
                        if code:
                            raise ValueError("генератор комнат игры не принял изменения:\n" + out)
                        regenerated = True
                    rooms = changed_rooms(before, written) if any(t in written for t in ROOM_TABLES) else []
                    if rooms != []:
                        code, out = run([sys.executable, "tools/rooms/generate_rooms.py", *(rooms or [])])
                        if code:
                            raise ValueError("генератор комнат не принял изменения:\n" + out)
                        regenerated = True
                        # Room generation owns scenes, not the already-painted panels — but a
                        # composed room's picture is what the send was for.
                        restore_files({p: raw for p, raw in before.items()
                                       if "assets/levels/" in (rel := p.relative_to(ROOT).as_posix()) and not rel.startswith(COMPOSED_OUT)})
                    if any(w.startswith("tools/studio/overrides/") for w in written):
                        manifest = ROOT / "tools/studio/overrides/overrides.json"
                        old = json.loads(before.get(manifest, b"{}"))
                        new = json.loads(manifest.read_text(encoding="utf-8"))
                        keep = {rel for rel in old.keys() | new.keys() if old.get(rel) != new.get(rel)}
                        for rel in new:
                            edit = "tools/studio/overrides/" + rel
                            mask = edit[:-4] + ".mask.png"
                            if edit in written or mask in written:
                                keep.add(rel)
                        # only the generators of these edits, each for just their pictures where it can
                        # (studio_overrides.NARROWS): the rest are restored below anyway
                        if keep:
                            code, out = run([sys.executable, "tools/art/studio_overrides.py", "regenerate", *sorted(keep)])
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
                    if PACK is not None and any(w.startswith("content/localization/") for w in written):
                        # Godot reads one strings.csv: lay the pack's over the engine's again
                        code, out = run([sys.executable, "tools/packs/apply_pack.py", str(PACK), "--force"])
                        if code:
                            raise ValueError("не удалось разложить строки игры:\n" + out)
                    code, out = run(build_data_cmd())
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
            if self.path in ("/api/validate", "/api/run", "/api/check") and not g:
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
                extra = ["--composed"] if data.get("composed") else []
                subprocess.Popen([g, "--path", str(ROOT), "scenes/run/run.tscn", "--", f"room={room}"] + extra, cwd=ROOT)
                return self._json(200, {"ok": True})
            if self.path == "/api/check":
                room = str(data.get("room", ""))
                if not room.replace("_", "").isalnum():
                    raise ValueError("bad room name")
                if PACK is not None:
                    raise ValueError("проверка ботом пока только для комнат Ashes; путь комнаты игры проверил генератор (--pack)")
                if not (ROOT / "scenes/rooms/composed" / (room + ".tscn")).exists():
                    raise ValueError("у комнаты нет черновика: сначала «→ В игру»")
                results = []
                with WRITE_LOCK:
                    run([g, "--headless", "--path", str(ROOT), "--import"])
                    for name, flags, args in CHECKS:
                        code, out = run([g, "--headless", *flags, "--path", str(ROOT), "-s", f"scripts/tools/{name}.gd", "--",
                                         *[a.format(room=room) for a in args]], timeout=1800)
                        results.append({"test": name, "ok": code == 0, "log": out[-3000:]})
                return self._json(200, {"ok": all(r["ok"] for r in results), "results": results})
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


def build_data_cmd():
    # the pictures it read last time, kept beside its data: a write rebuilds it, and most of them are as they were
    cmd = [sys.executable, "tools/studio/build_data.py", "--png-cache", "tools/studio/import/.png_cache.json"]
    if PACK is not None:
        remote = subprocess.run(["git", "remote", "get-url", "origin"], cwd=PACK, capture_output=True, text=True).stdout.strip()
        repo = remote.removesuffix(".git").replace("git@github.com:", "https://github.com/").split("github.com/")[-1] if "github.com" in remote else ""
        cmd += ["--repo", repo]
    return cmd


def main():
    global PACK
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", type=Path, help="a game pack's folder: edit that game instead of Ashes of Eden")
    args = ap.parse_args()
    if args.game:
        PACK = args.game.resolve()
        subprocess.run([sys.executable, str(ROOT / "tools/packs/apply_pack.py"), str(PACK), "--force"], check=True)
        g = godot()
        if g:
            subprocess.run([g, "--headless", "--path", str(ROOT), "--import"], capture_output=True)
    elif (ROOT / "content/data/game.json").exists():
        print("content/ holds a game pack: restart with --game <its folder> to write into it, "
              "or python3 tools/packs/apply_pack.py --restore for Ashes", file=sys.stderr)
        sys.exit(1)
    if PACK is not None or not (ROOT / "tools/studio/import/meta.json").exists():
        print("building the studio's data first (tools/studio/build_data.py)…")
        subprocess.run(build_data_cmd(), cwd=ROOT, check=True)
    print(f"Studio: http://localhost:{PORT}/tools/studio/  (writes into {PACK or ROOT})")
    Server(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
