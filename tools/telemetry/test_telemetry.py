"""The telemetry receiver and pull.py, end to end on a local port.

    python3 -m unittest discover -s tools/telemetry
"""

import json
import pathlib
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import pull  # noqa: E402
import server  # noqa: E402
import set_urls  # noqa: E402


def night(install, nid, nights=0, died=True, gift=True, skipped=True, rooms=3, daily="", try_=0, online=False):
    events = [{"e": "run_start", "t": 0}, {"e": "room_start", "room": "village_night", "index": 1, "t": 0},
              {"e": "room_clear", "room": "village_night", "seconds": 30, "damage": 0.2, "deaths": 0, "t": 30}]
    if gift:
        events.append({"e": "gift", "id": "vampirism", "t": 40})
    for i in range(2, rooms + 1):
        events.append({"e": "room_start", "room": f"r{i}", "index": i, "t": 40 + i})
    if skipped:
        events.append({"e": "skip", "dialogue": "ch1_stranger", "t": 60})
    else:
        events.append({"e": "choice", "dialogue": "ch1_stranger", "choice": "trust", "t": 60})
    if died:
        events.append({"e": "death", "room": f"r{rooms}", "x": 0, "y": 0, "by": "possessed", "t": 90})
    events.append({"e": "run_end", "won": False, "seconds": 90, "level": 2, "gifts": 1, "omen": "", "vial": 0, "t": 90})
    return {"format": 1, "id": nid, "install": install, "nights": nights, "daily": daily, "daily_try": try_,
            "online": online, "events": events}


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.data = pathlib.Path(self.dir.name)
        self.httpd = server.serve(0, self.data, "127.0.0.1", token="sesame")
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.dir.cleanup()

    def post(self, payload, raw=None, kind="text/plain"):
        body = raw if raw is not None else json.dumps(payload).encode()
        request = urllib.request.Request(self.url + "/collect", data=body, method="POST",
                                         headers={"Content-Type": kind})
        try:
            with urllib.request.urlopen(request, timeout=5) as answer:
                return answer.status, dict(answer.headers)
        except urllib.error.HTTPError as error:
            return error.code, dict(error.headers)

    def test_collects_and_exports(self):
        status, headers = self.post({"format": 1, "records": [night("a", "n1"), night("a", "n2")]})
        self.assertEqual(status, 200)
        self.assertEqual(headers.get("Access-Control-Allow-Origin"), "*")
        lines = "".join(p.read_text() for p in self.data.glob("records-*.jsonl")).splitlines()
        self.assertEqual(len(lines), 2)
        self.assertIn("received", json.loads(lines[0]))
        self.assertNotIn("127.0.0.1", "".join(lines), "no address is kept")
        request = urllib.request.Request(self.url + "/export", headers={"Authorization": "Bearer sesame"})
        with urllib.request.urlopen(request, timeout=5) as answer:
            self.assertEqual(len(answer.read().decode().splitlines()), 2)

    def test_export_needs_the_token(self):
        request = urllib.request.Request(self.url + "/export", headers={"Authorization": "Bearer nope"})
        with self.assertRaises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(request, timeout=5)
        self.assertEqual(caught.exception.code, 403)

    def test_preflight(self):
        request = urllib.request.Request(self.url + "/collect", method="OPTIONS")
        with urllib.request.urlopen(request, timeout=5) as answer:
            self.assertEqual(answer.status, 204)
            self.assertIn("POST", answer.headers["Access-Control-Allow-Methods"])

    def test_refuses_bad_batches(self):
        self.assertEqual(self.post(None, raw=b"not json")[0], 400)
        self.assertEqual(self.post({"format": 99, "records": [night("a", "x")]})[0], 400)
        self.assertEqual(self.post({"format": 1, "records": [{"no": "id"}]})[0], 400)
        self.assertEqual(self.post({"format": 1, "records": [night("a", str(i)) for i in range(50)]})[0], 400)
        self.assertEqual(list(self.data.glob("records-*.jsonl")), [])

    def test_rate_limit(self):
        limit = server.RateLimit(count=3, window=10)
        self.assertTrue(all(limit.allow("x", now=t) for t in (0, 1, 2)))
        self.assertFalse(limit.allow("x", now=3))
        self.assertTrue(limit.allow("y", now=3), "another address is not held back")
        self.assertTrue(limit.allow("x", now=11), "the window moves on")


class PullTest(unittest.TestCase):
    def test_four_numbers_and_playtests(self):
        records = [
            night("a", "1"), night("a", "1"),  # resent: once
            {"kind": "retry", "id": "r1", "install": "a", "nights": 1},
            night("b", "2", gift=False, died=True, rooms=2, skipped=False),
            night("c", "3", rooms=5),
            night("c", "4", nights=1),  # not a first night
            night("d", "5", daily="2026-10-14", try_=2),  # a second daily try: left out
            night("e", "6", online=True),  # online: left out
        ]
        numbers = pull.four_numbers(pull.unique(records))
        self.assertEqual(numbers["first_nights"], 3)
        self.assertAlmostEqual(numbers["first_gift"], 2 / 3)
        self.assertEqual(numbers["first_death_room"], 3)
        self.assertAlmostEqual(numbers["retry"], 1 / 3)
        self.assertEqual(numbers["stranger_met"], 3)
        self.assertAlmostEqual(numbers["stranger_skipped"], 2 / 3)
        self.assertIn("| Pressed «Again» after the first death | 33 % |", pull.report(numbers))
        with tempfile.TemporaryDirectory() as folder:
            written = pull.write_playtests(pull.nights_of(pull.unique(records)), pathlib.Path(folder))
            self.assertEqual(written, 6)
            first = sorted(pathlib.Path(folder).glob("*.jsonl"))[0].read_text().splitlines()
            self.assertEqual(json.loads(first[0])["e"], "run_start")
            self.assertEqual(json.loads(first[-1])["e"], "run_end")


class SetUrlsTest(unittest.TestCase):
    def test_writes_only_what_is_set(self):
        project = (pathlib.Path(__file__).resolve().parents[2] / "project.godot").read_text(encoding="utf-8")
        self.assertIn('telemetry/url=""', project, "the repository ships with no server")
        self.assertEqual(set_urls.apply(project, {}), project, "no variables: the build is unchanged")
        after = set_urls.apply(project, {"TELEMETRY_URL": "https://t.example.org/collect"})
        self.assertIn('telemetry/url="https://t.example.org/collect"', after)
        self.assertIn('telemetry/feedback_url=""', after)
        self.assertEqual(after.count("telemetry/url="), 1)
        with self.assertRaises(SystemExit):
            set_urls.apply(project, {"FEEDBACK_URL": "http://plain.example.org"})


if __name__ == "__main__":
    unittest.main()
