#!/usr/bin/env python3
"""Is the loading page still a page that works?

`tools/check_generators.py` proves shell.html is what the generator writes.
It says nothing about whether what the generator writes is any good, and the
shell is the one file in the repository that nothing else tests: it is not
GDScript, so the validator never sees it; it is not exported by the project,
so a headless run never loads it; and the first time a mistake in it shows up
is a blank page in somebody's browser.

So this checks the few things that can actually be checked without a browser:
the script parses, the exporter's placeholders are the ones it substitutes,
no generator marker was left behind, both pictures decode, and the page is
small enough to be worth putting in front of a 100 MB download.

    python3 tools/web/check_shell.py

Exit code 1 on anything wrong.
"""
import base64, io, os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHELL = os.path.join(ROOT, "tools", "web", "shell.html")

## What Godot's Web exporter substitutes in a custom shell. Anything else
## spelled $GODOT_… survives into the deployed page as literal text.
KNOWN = {"$GODOT_URL", "$GODOT_PROJECT_NAME", "$GODOT_HEAD_INCLUDE",
         "$GODOT_CONFIG", "$GODOT_SPLASH_COLOR", "$GODOT_THREADS_ENABLED"}

## The page is downloaded before anything else and cannot be cached on a
## first visit, so it is the one file where a few hundred KB is a real cost.
## The two inlined pictures are about 135 KB of it.
MAX_KB = 400

problems = []


def complain(message):
    problems.append(message)


def main():
    if not os.path.exists(SHELL):
        sys.exit("missing tools/web/shell.html — run tools/art/make_web_gate.py")
    html = open(SHELL, encoding="utf-8").read()

    size_kb = os.path.getsize(SHELL) // 1024
    if size_kb > MAX_KB:
        complain("the page is %d KB, over the %d KB this file is worth" % (size_kb, MAX_KB))

    left = re.findall(r"__[A-Z_]+__", html)
    if left:
        complain("generator markers left in the output: %s — the template gained a "
                 "placeholder make_web_gate.py does not fill" % ", ".join(sorted(set(left))))

    used = set(re.findall(r"\$GODOT_[A-Z_]+", html))
    unknown = used - KNOWN
    if unknown:
        complain("the exporter does not substitute %s; it will ship as literal text"
                 % ", ".join(sorted(unknown)))
    if "$GODOT_URL" not in used:
        complain("no $GODOT_URL — the page would never load the engine")
    if "$GODOT_CONFIG" not in used:
        complain("no $GODOT_CONFIG — the engine would start with no configuration")

    # The click is the whole reason this shell exists: a browser will not open
    # an audio context without one, so startGame has to be inside a handler.
    script = re.search(r"<script>\n(.*?)\n\t</script>", html, re.S)
    if not script:
        complain("no inline script block to check")
    else:
        body = script.group(1)
        if "addEventListener" not in body or "startGame" not in body:
            complain("startGame is not behind a listener — the build would come up mute")
        check_syntax(body)

    pictures = re.findall(r'url\("data:(image/\w+);base64,([^"]+)"\)', html)
    if len(pictures) != 2:
        complain("expected the backdrop and the sprite sheet inlined, found %d picture(s)"
                 % len(pictures))
    for mime, payload in pictures:
        try:
            from PIL import Image
            with Image.open(io.BytesIO(base64.b64decode(payload))) as img:
                img.load()
        except ImportError:
            break
        except Exception as err:
            complain("an inlined %s does not decode: %s" % (mime, err))

    if problems:
        print("shell.html:", file=sys.stderr)
        for problem in problems:
            print("  " + problem, file=sys.stderr)
        sys.exit(1)
    print("shell.html: %d KB, %d picture(s), script parses, placeholders are the "
          "exporter's" % (size_kb, len(pictures)))


def check_syntax(body):
    """Node, if it is here. A syntax error in the shell is a blank page."""
    node = shutil.which("node")
    if not node:
        print("note: node not found, script syntax unchecked", file=sys.stderr)
        return
    # The placeholders are not JavaScript until the exporter fills them.
    stub = ("class Engine { static getMissingFeatures() { return []; } }\n"
            + body.replace("$GODOT_CONFIG", "{}")
                  .replace("$GODOT_THREADS_ENABLED", "false"))
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as handle:
        handle.write(stub)
        path = handle.name
    try:
        result = subprocess.run([node, "--check", path], capture_output=True, text=True)
        if result.returncode != 0:
            complain("the script does not parse:\n      "
                     + result.stderr.strip().replace("\n", "\n      ")[:500])
    finally:
        os.unlink(path)


if __name__ == "__main__":
    main()
