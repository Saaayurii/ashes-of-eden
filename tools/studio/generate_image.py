#!/usr/bin/env python3
"""Generates one picture for the art studio with the OpenAI image API.

The studio asks for a picture without holding a key: it pushes a request to
a studio-gen/<login> branch (tools/studio/requests/<id>/request.json beside its
reference pictures), .github/workflows/studio-images.yml runs this with the
repository secret OPENAI_API_KEY and pushes out.png back. Served locally,
tools/studio/serve.py runs it with the key from the environment.

    OPENAI_API_KEY=… python3 tools/studio/generate_image.py path/to/request.json

request.json: {"prompt", "size", "quality", "model", "transparent", "fidelity",
               "refs": ["ref0.png", …] (beside it), "out": "out.png"}
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API = "https://api.openai.com/v1/images/"


def multipart(fields, files):
    """multipart/form-data by hand: the standard library has no encoder for it."""
    boundary = uuid.uuid4().hex
    body = b""
    for name, value in fields:
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
    for name, path in files:
        body += (f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="{path.name}"\r\n'
                 f"Content-Type: image/png\r\n\r\n").encode() + path.read_bytes() + b"\r\n"
    return body + f"--{boundary}--\r\n".encode(), f"multipart/form-data; boundary={boundary}"


def request(req: dict, base: Path, key: str, fidelity: bool) -> bytes:
    refs = [base / r for r in req.get("refs", [])]
    common = [("model", req.get("model") or "gpt-image-1"), ("prompt", req["prompt"]), ("size", req.get("size", "1024x1024")),
              ("quality", req.get("quality", "medium")), ("n", "1")]
    if req.get("transparent"):
        common.append(("background", "transparent"))
    if refs:
        if fidelity:
            common.append(("input_fidelity", "high"))
        body, ctype = multipart(common, [("image[]", r) for r in refs])
        url = API + "edits"
    else:
        body, ctype, url = json.dumps(dict(common) | {"n": 1}).encode(), "application/json", API + "generations"
    r = urllib.request.Request(url, data=body, headers={"Authorization": "Bearer " + key, "Content-Type": ctype})
    with urllib.request.urlopen(r, timeout=300) as resp:
        data = json.load(resp)
    return base64.b64decode(data["data"][0]["b64_json"])


def generate(path: Path) -> Path:
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        raise SystemExit("OPENAI_API_KEY is not set: the repository owner adds it in Settings → Secrets and variables → Actions")
    req = json.loads(path.read_text(encoding="utf-8"))
    fidelity = bool(req.get("fidelity"))
    try:
        png = request(req, path.parent, key, fidelity)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        if fidelity and "input_fidelity" in detail:  # a model that does not take it
            png = request(req, path.parent, key, False)
        else:
            raise SystemExit(f"OpenAI refused the request ({e.code}): {detail[:500]}")
    out = path.parent / req.get("out", "out.png")
    out.write_bytes(png)
    print("wrote", out)
    return out


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
