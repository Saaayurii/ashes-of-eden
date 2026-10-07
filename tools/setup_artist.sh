#!/usr/bin/env bash
# Everything an artist's computer needs for the art pipeline (docs/ARTIST.md),
# installed once and safe to run again: it only adds what is missing.
#
#   bash tools/setup_artist.sh
#
# 1. Python 3 with Pillow, NumPy, SciPy (the studio's tools and ref2game's
#    gen.py / compare.py / rigcut.py);
# 2. Node.js 18+ (the studio's tests, ref2game's checks);
# 3. ref2game's Playwright + Chromium, inside the skill folder
#    (.claude/skills/ref2game/scripts/node_modules, git-ignored);
# 4. the studio's own browser test dependencies are left to CI.
# macOS and Linux. Nothing here needs sudo except a missing system package,
# which it names instead of installing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OS="$(uname -s)"
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
miss() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILED=1; }
FAILED=0

hint() {  # how to install a missing tool on this system
  case "$OS" in
    Darwin) echo "brew install $1   (Homebrew: https://brew.sh)";;
    *) echo "sudo apt install $2   (or your distribution's package)";;
  esac
}

echo "Python"
if command -v python3 >/dev/null; then
  ok "$(python3 --version)"
  if python3 -c 'import PIL, numpy, scipy' 2>/dev/null; then ok "Pillow, NumPy, SciPy"
  else
    echo "  installing Pillow, NumPy, SciPy for this user"
    python3 -m pip install --user --quiet pillow numpy scipy 2>/dev/null \
      || python3 -m pip install --user --quiet --break-system-packages pillow numpy scipy \
      || true
    python3 -c 'import PIL, numpy, scipy' 2>/dev/null && ok "Pillow, NumPy, SciPy" \
      || miss "Pillow/NumPy/SciPy: python3 -m pip install --user pillow numpy scipy"
  fi
else
  miss "python3 — $(hint python python3)"
fi

echo "Node.js"
if command -v node >/dev/null; then
  major="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "$major" -ge 18 ]; then ok "node $(node --version)"; else miss "node $(node --version) is too old, 18+ — $(hint node nodejs)"; fi
else
  miss "node — $(hint node nodejs)"
fi

echo "ref2game (rigs, checks, Playwright)"
R2G="$ROOT/.claude/skills/ref2game"
if [ ! -d "$R2G/scripts" ]; then
  miss "the ref2game skill is not in this checkout (.claude/skills/ref2game) — git pull"
elif command -v node >/dev/null; then
  if (cd "$R2G/scripts" && node -e "require.resolve('playwright')" 2>/dev/null); then ok "Playwright"
  else
    echo "  installing Playwright into the skill (once)"
    (cd "$R2G/scripts" && npm install --silent --no-audit --no-fund) && ok "Playwright" || miss "Playwright: cd $R2G/scripts && npm install"
  fi
  if (cd "$R2G/scripts" && npx --yes playwright install chromium >/dev/null 2>&1); then ok "Chromium for Playwright"
  else miss "Chromium: cd $R2G/scripts && npx playwright install chromium"; fi
fi

echo "Optional"
command -v gh >/dev/null && ok "GitHub CLI" || echo "  · GitHub CLI not found (not needed: the studio sends through GitHub itself) — $(hint gh gh)"
command -v ffmpeg >/dev/null && ok "ffmpeg" || echo "  · ffmpeg not found (only for studying a video reference) — $(hint ffmpeg ffmpeg)"
[ -x /Applications/Godot.app/Contents/MacOS/Godot ] || command -v godot >/dev/null \
  && ok "Godot" || echo "  · Godot not found (not needed: the sandbox plays the game in the browser)"

echo
if [ "$FAILED" = 0 ]; then echo "Готово. Всё на месте."; else echo "Не хватает того, что отмечено ✗ выше."; exit 1; fi
