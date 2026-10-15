#!/usr/bin/env python3
"""Every painted picture the Web build pays for stays lossy WebP.

.gitignore ignores every *.import and lets through, by name, the pictures that
are painted rather than pixel art (`!assets/levels/*_wide.png.import`, …): those
import as lossy WebP, which costs nothing anybody can see and saves the Web
player most of the download. A picture that matches one of those lines but
whose .import is missing (a fresh checkout re-imports it lossless) or says
`compress/mode=0` (Godot's default, copied along with a new picture) quietly
puts megabytes back. This fails on either, naming the file.

Run from the repository root: python3 tools/export/check_lossy.py
"""
import fnmatch
import subprocess
import sys
from pathlib import Path


def lossy_globs(gitignore: Path) -> list[str]:
    out = []
    for line in gitignore.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("!") and line.endswith(".png.import"):
            out.append(line[1:].removesuffix(".import"))
    return out


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    globs = lossy_globs(root / ".gitignore")
    tracked = set(subprocess.run(["git", "ls-files"], cwd=root, capture_output=True,
                                 text=True, check=True).stdout.splitlines())
    problems = []
    for png in sorted(p for p in tracked if p.endswith(".png")):
        # fnmatch's * crosses "/", git's does not: compare directory by directory
        if not any(fnmatch.fnmatch(png, g) and png.count("/") == g.count("/") for g in globs):
            continue
        imp = png + ".import"
        if imp not in tracked:
            problems.append(f"{imp}: not committed, so CI imports {png} lossless")
            continue
        params = (root / imp).read_text(encoding="utf-8")
        if "compress/mode=1" not in params.splitlines():
            problems.append(f"{imp}: compress/mode is not 1 (lossy WebP)")
    for p in problems:
        print(p)
    print(f"{len(problems)} painted picture(s) not lossy" if problems else "every painted picture is lossy WebP")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
