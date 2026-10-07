# ref2game, vendored

A plain copy of the `claude/` edition of <https://github.com/studioigor/ref2game>
at commit `61d8f9e5457b9b3a379fa016621efcf1904ce249` (2026-10-06), MIT
(`LICENSE`, copied from the upstream root).

It is a copy on purpose: no submodule, no subtree remote, nothing that fetches
or updates it from GitHub. A change here is a reviewed pull request like any
other. To take a newer upstream, copy the files again by hand and update the
commit above.

Local changes:
- `scripts/package.json`: Playwright pinned to `1.49.1` (upstream `^1.47.0`),
  the same version the studio's browser test uses.

What reaches the network, so nobody is surprised:
- `scripts/setup.sh`: `pip install pillow numpy scipy` when they are missing,
  `npm install` of the pinned Playwright into `scripts/node_modules`
  (git-ignored), `npx playwright install chromium`. Nothing else.
- `scripts/gen.py`: the image providers' own APIs, only when asked to generate.
  In this project images come from her browser ChatGPT, so it is used for its
  offline tools (`key`, `validate`, `pixel`).
- `templates/live/index.html`: polls its own local server for hot reload.

Used by `.claude/skills/ashes-art/SKILL.md` for its method and tools (study,
compare, sheets, the rig maths that `tools/studio/js/rig-core.js` ports); its
WebGL engine is not where this game's art is judged.
