#!/usr/bin/env python3
"""Writes the telemetry server and the feedback form into project.godot for a
build (docs/PLAYTEST.md), from TELEMETRY_URL and FEEDBACK_URL — the CI
workflows pass the repository variables of the same names. An unset or empty
variable leaves its line as it is (empty in the repository: off, hidden), so a
fork without them builds exactly what it always did.

    TELEMETRY_URL=https://t.example.org/collect python3 tools/telemetry/set_urls.py
"""

import os
import pathlib
import re
import sys

KEYS = {"TELEMETRY_URL": "telemetry/url", "FEEDBACK_URL": "telemetry/feedback_url"}


def apply(text: str, env: dict) -> str:
    for var, key in KEYS.items():
        url = env.get(var, "").strip()
        if not url:
            continue
        if not url.startswith("https://") or '"' in url or "\n" in url:
            raise SystemExit(f"{var} must be an https:// address")
        line = f'{key}="{url}"'
        pattern = re.compile(rf"^{re.escape(key)}=.*$", re.M)
        if pattern.search(text):
            text = pattern.sub(lambda _: line, text, count=1)
        elif "\n[ashes]\n" in text:
            text = text.replace("\n[ashes]\n", f"\n[ashes]\n\n{line}\n", 1)
        else:
            text = text.rstrip("\n") + f"\n\n[ashes]\n\n{line}\n"
    return text


def main() -> int:
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "project.godot")
    before = path.read_text(encoding="utf-8")
    after = apply(before, dict(os.environ))
    if after != before:
        path.write_text(after, encoding="utf-8")
        print("telemetry: build sends to", ", ".join(v for v in KEYS if os.environ.get(v)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
