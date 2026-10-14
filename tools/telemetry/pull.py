#!/usr/bin/env python3
"""Turns what players sent (tools/telemetry/server.py) into what the game's own
tools already read.

    TELEMETRY_TOKEN=secret python3 tools/telemetry/pull.py --url https://telemetry.example.org
    python3 tools/telemetry/pull.py --file build/telemetry/records-2026-10.jsonl

Writes, under --out (build/telemetry/field by default):
    playtest/<received>_<install>_<id>.jsonl   one per night, the Playtest
        autoload's own format, which scripts/tools/balance_probe.gd reads with
        `-- playtests=<that folder>` (make probe-field);
    four_numbers.md   docs/CORE_LOOP.md's four numbers, measured.

Records are counted once by id however many times a batch was resent. A night
of the day counts only its first try of that day; nights played online are
left out of the four numbers (the other player shaped them).
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import statistics
import sys
import urllib.request

# docs/CORE_LOOP.md: the one blocking talk of the first night. A game pack with
# another one passes --stranger.
STRANGER = "ch1_stranger"


def read_lines(text: str) -> list[dict]:
    out = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict) and isinstance(record.get("id"), str):
            out.append(record)
    return out


def fetch(url: str, token: str) -> str:
    request = urllib.request.Request(url.rstrip("/") + "/export",
                                     headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request, timeout=60) as answer:
        return answer.read().decode("utf-8")


def unique(records: list[dict]) -> list[dict]:
    seen = set()
    out = []
    for record in records:
        if record["id"] in seen:
            continue
        seen.add(record["id"])
        out.append(record)
    return out


def nights_of(records: list[dict]) -> list[dict]:
    return [r for r in records if r.get("kind", "night") == "night" and isinstance(r.get("events"), list)]


def counted(night: dict) -> bool:
    """Whether a night speaks for the four numbers."""
    if night.get("online"):
        return False
    return not night.get("daily") or int(night.get("daily_try", 1)) <= 1


def safe(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "", str(text))[:16] or "x"


def write_playtests(nights: list[dict], folder: pathlib.Path) -> int:
    folder.mkdir(parents=True, exist_ok=True)
    written = 0
    for night in nights:
        name = f"{safe(night.get('received', 'day'))}_{safe(night.get('install', ''))[:8]}_{safe(night['id'])}.jsonl"
        path = folder / name
        if path.exists():
            continue
        with open(path, "w", encoding="utf-8") as out:
            for event in night["events"]:
                if isinstance(event, dict) and "e" in event:
                    out.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n")
        written += 1
    return written


def summary_of(night: dict) -> dict:
    """The record's own summary, or the same rebuilt from its events (Telemetry.summarise)."""
    if isinstance(night.get("summary"), dict):
        return night["summary"]
    out = {"rooms": 0, "died": False, "first_gift_t": -1.0, "skipped": [], "choices": {}}
    for e in night["events"]:
        kind = e.get("e")
        if kind == "room_start":
            out["rooms"] = max(out["rooms"], int(e.get("index", 0)))
        elif kind in ("gift", "refuse") and out["first_gift_t"] < 0:
            out["first_gift_t"] = float(e.get("t", 0))
        elif kind == "skip":
            out["skipped"].append(e.get("dialogue", ""))
        elif kind == "choice":
            out["choices"][e.get("dialogue", "")] = e.get("choice", "")
        elif kind == "death":
            out["died"] = True
    return out


def four_numbers(records: list[dict], stranger: str = STRANGER) -> dict:
    nights = [n for n in nights_of(records) if counted(n)]
    retries = [r for r in records if r.get("kind") == "retry"]
    first: dict[str, dict] = {}
    for night in nights:
        if int(night.get("nights", -1)) == 0 and night.get("install"):
            first.setdefault(night["install"], night)
    first_nights = list(first.values())
    reached_gift = [n for n in first_nights if float(summary_of(n).get("first_gift_t", -1)) >= 0]
    died = [n for n in first_nights if summary_of(n).get("died")]
    death_rooms = [int(summary_of(n).get("rooms", 0)) for n in died]
    retried_installs = {r.get("install") for r in retries if int(r.get("nights", 99)) <= 1 and not r.get("daily")}
    retried = [n for n in died if n.get("install") in retried_installs]
    met: dict[str, bool] = {}
    for night in nights:
        summary = summary_of(night)
        skipped = stranger in summary.get("skipped", [])
        if (skipped or stranger in summary.get("choices", {})) and night.get("install") not in met:
            met[night.get("install")] = skipped

    def share(part, whole):
        return (len(part) / len(whole)) if whole else None

    return {
        "installs": len({n.get("install") for n in nights}),
        "nights": len(nights),
        "first_nights": len(first_nights),
        "first_gift": share(reached_gift, first_nights),
        "first_death_room": statistics.median(death_rooms) if death_rooms else None,
        "first_deaths": len(died),
        "retry": share(retried, died),
        "stranger_met": len(met),
        "stranger_skipped": (sum(met.values()) / len(met)) if met else None,
    }


def report(numbers: dict) -> str:
    def pct(value):
        return "—" if value is None else f"{value * 100:.0f} %"

    def num(value):
        return "—" if value is None else f"{value:g}"

    return "\n".join([
        "# The four numbers (docs/CORE_LOOP.md), from players",
        "",
        f"{numbers['installs']} installs, {numbers['nights']} nights counted, "
        f"{numbers['first_nights']} first nights.",
        "",
        "| Number | Measured | Target |",
        "|---|---|---|",
        f"| Reached the first gift on the first night | {pct(numbers['first_gift'])} | > 90 % |",
        f"| Room of the first death (median, of {numbers['first_deaths']}) | {num(numbers['first_death_room'])} | 4 |",
        f"| Pressed «Again» after the first death | {pct(numbers['retry'])} | > 60 % |",
        f"| Skipped the stranger (of {numbers['stranger_met']} who met him) | {pct(numbers['stranger_skipped'])} | < 70 % |",
        "",
    ])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--url", help="the server (its /export, with TELEMETRY_TOKEN)")
    parser.add_argument("--file", action="append", default=[], help="a records-*.jsonl file (repeatable)")
    parser.add_argument("--out", default="build/telemetry/field")
    parser.add_argument("--stranger", default=STRANGER)
    args = parser.parse_args(argv)
    text = ""
    if args.url:
        token = os.environ.get("TELEMETRY_TOKEN", "")
        if not token:
            print("TELEMETRY_TOKEN is not set", file=sys.stderr)
            return 2
        text += fetch(args.url, token)
    for path in args.file:
        text += pathlib.Path(path).read_text(encoding="utf-8") + "\n"
    if not args.url and not args.file:
        parser.error("give --url or --file")
    records = unique(read_lines(text))
    out = pathlib.Path(args.out)
    written = write_playtests(nights_of(records), out / "playtest")
    numbers = four_numbers(records, args.stranger)
    (out / "four_numbers.md").write_text(report(numbers), encoding="utf-8")
    print(f"{len(records)} records, {written} new nights in {out / 'playtest'}")
    print(report(numbers))
    return 0


if __name__ == "__main__":
    sys.exit(main())
