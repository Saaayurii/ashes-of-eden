# The room composer

A painted room is one 1280×720 picture, widened by a band or two. That is as big
as one picture from an image model gets, and it makes a small room. The art
studio's **«Конструктор»** puts several pictures together instead — two in a
row, two by two, an L — and the rooms generator paints them into one picture,
stitching every seam.

## What it writes

`tools/rooms/composed_rooms.json`, one entry per room it is made for:

```json
{"graveyard_cross": {
    "live": false,
    "cells": [{"painting": "graveyard_cross", "col": 0, "row": 0},
              {"painting": "panels/graveyard_hill", "col": 1, "row": 0}],
    "ground": [[x, y, w, h]], "ledges": [...], "platforms": [...],
    "crumbling_platforms": [[x, y, w], [x, y, w, "timber"]],
    "ramps": [[x0, y0, x1, y1]], "hazards": [[x, y, w, h]],
    "player": [x, y], "door": [x, y],
    "spawns": [[id, x, y]], "props": [[id, x, y]], "npcs": [[id, x, y]],
    "windows": [{"points": [[x, y], ...], "depth": 0.84, "sky": false}],
    "lights": [[x, y, "#ffb060", radius, energy, flicker]],
    "front": [{"from": "graveyard_cross", "crop": [x, y, w, h], "at": [x, y], "depth": 1.35}]}}
```

- **Cells.** A grid of at most 6×4. Cell (col, row) starts at (col·1280, row·720).
  Every painting must be 1280×720. A painting is either one the game already has
  (`assets/levels/<stem>.png`) or a new one the studio uploads
  (`assets/levels/panels/<stem>.png`, fitted to the cell, cropped from the
  centre). A hole in the grid is filled from its first neighbour (left, right,
  above, below), mirrored, which fades over `HOLE_FADE` px into night: the darkest
  tenth of the paintings. The picture then runs on into the dark instead of
  stopping at a black wall. Fill the hole, or keep the walk away from it.
- **Layers** (`windows`, `lights`, `front`): when left out, the room uses its
  cells' own. Written, they are the studio's. See [DEPTH.md](DEPTH.md).
- **Coordinates** are in the finished room's pixels, not panel pixels.
- **Crumbling platforms** (`scripts/rooms/crumbling_platform.gd`) are
  `[x, y, w]`, or `[x, y, w, kind]` with kind `stone` (the default) or `timber`:
  a foothold that gives way under the hero and grows back, written into the
  scene exactly as a painted room's `crumbling_platforms`. As in a painted room,
  the route never counts on one — `check_reach`, the studio's `composeReach` and
  `reach_test.gd` all leave it out — so the way through must hold without it.
  It is a shortcut over a gap, not the bridge.
- **The key** names the painted room the composition is made for. The composed
  room keeps that room's ambient light, fog, music, weather, intro caption and
  cutscenes. It keeps none of its geometry, which is all in the entry.

## Draft and live

- **A draft** (`"live": false`) is built beside its room. The scene goes to
  `scenes/rooms/composed/<name>.tscn` and the picture to
  `assets/levels/composed/<name>.png`. The night still walks the old room. To
  open the draft:

  ```
  Godot --path . scenes/run/run.tscn -- room=<name> --composed
  ```

  You can also press «▶ В Godot» in the studio's local mode. A draft is never
  autosaved, and its chapter card is its room's. If its route does not hold, the
  generator says so and writes it anyway.
- **A live room** (`"live": true`) replaces the room the night walks through.
  `check_reach` must prove it, as it does any room, or the generator fails. Its
  draft scene is removed.

The existing rooms are untouched until a composition of them is made live.

## How the seams are stitched

See `compose._join`. First the two pictures' light is evened out (`_tone`):
row by row, averaged over `TONE_ROWS`, each side is multiplied halfway toward
the other's light — fully at the seam, not at all `TONE` (320) px away, never
by more than `TONE_LIMIT` — so a torch-lit vault beside a cold crypt meets it
at one light instead of along a line. A gain, not an offset: a dark stays dark.
Then each side is carried past the seam by its own mirror, so
both pictures cover the same 2×96 px band. A min-cost path runs through the
middle half of the band, where the two agree best. Each side bends its light
halfway toward the other's once more, for what the wide pass left, fading out
toward its own edge. Beyond `TONE` each picture is exactly its own. A row of cells is joined first, then the rows are joined
top to bottom the same way (transposed).

Unless the studio placed them, candles come from each panel's own `.lights.json`,
or from the tracer for a new painting, moved into their cell.

**The far plane.** Unless the studio drew its own openings, a cell brings its
room's far openings (`FAR_WINDOWS`), moved into the cell. Each opening keeps its
room's depth for its number, and the first one is sky. The plate behind them is
stitched like the picture, from each cell's inpainted plate
(`assets/levels/depth/<room>_backfill.png`; for a new painting, the painting
itself). It is written to `assets/levels/composed/<name>_backfill.png`. The
travel per pixel of camera (`depth_parallax`) is the mean of the cells' rooms.

**The front plane** is the entry's `front`, baked by `tools/rooms/front.py`. A
composed room has no void kill line: a floor may run down to the edge of the map,
and falling out of the room is what kills.

Its backdrop life is its room's flames with no zones
(`BackdropLife.rule("composed/<name>")`), because the zones were drawn on another
picture. Give it zones of its own in `data/backdrops.json` under that key; the
studio's «Оживление» lists the composed pictures.

## The studio tab

- Pick a room. It starts from its own panel and its own ledges, enemies and
  things.
- Click «+» in the grid to add a painting. If the painting is another room's,
  the tab offers to bring that room's ledges, enemies and things with it,
  moved into the cell. «Заменить» and «Убрать клетку» act on the selected cell.
- **«Найти уступы»** runs the panel tracer (`traceLedges`, a port of
  `tools/rooms/trace_panel.py`, the same result to the pixel) over every cell.
  Each find shows as a yellow frame; click one to make it a ledge.
- **Editing by hand:**
  - Drag anything to move it.
  - Drag a selected rectangle's edges or corner to resize it.
  - Draw new ground, ledges, platforms, crumbling platforms («+ Осыпь»), ramps
    and hazards with the tools. A crumbling platform is dashed, has no height
    of its own, and its side panel picks stone or timber.
  - Place enemies and things, and change their kind in the side panel.
  - Delete removes the selection, Ctrl+Z undoes, the wheel zooms, and the right
    button or Space pans.
- **Views:**
  - «▦ Клетки» shows the pictures side by side. The orange bands are the seams.
  - «▤ Сшитый» shows the picture the generator will paint (`composeTiles`, a port
    of `compose.compose_tiles`; the stitch is the same to the value for whole
    pixels).
  - «◫ Объём» shows the three planes through the game's camera, and its tools
    edit the layers (see [DEPTH.md](DEPTH.md)).

  The «Швы» card lists every ledge edge and thing standing in a seam, because
  the picture there is the stitch's.
- **The hero's route** is checked as you edit (`composeReach`, a port of
  `painted_rooms.check_reach`). The panel lists what cannot be reached, marks it
  on the picture, and greys out surfaces off the route.
- **«→ В игру»** writes the table and any new paintings:
  - Locally, the server regenerates the rooms and runs the validator.
  - Online, it opens a pull request, and the studio robot regenerates the rooms
    on it.

  A live room whose route does not hold is refused.
- **«✓ Проверить в Godot»** (local) runs the engine's own checks on the draft
  (serve.py `/api/check`): `reach_test`, `stairs_test` and `void_fall_test`, each
  with `--composed <name>`. It takes minutes.
- **Playing it from Pages.** The pull request's preview link carries
  `&composed=1` for a draft (`make_preview_page.py`), so «▶ Играть с моими
  правками» opens the composed room, not the old one.

## Tests

- `tools/studio/tests/test_compose.py` covers:
  - the stitch keeps both pictures exact away from the seam;
  - a hole runs its neighbour on into the night;
  - openings and front pieces;
  - bad entries are refused;
  - the room table is the grid;
  - crumbling platforms are checked, carried to the generator, and never on the
    route.
- The engine tests take a draft with `-- --composed [room]`: `reach_test.gd`,
  `stairs_test.gd`, `void_fall_test.gd`.
- `tools/studio/tests/lib.test.js` covers:
  - reach, tracer, shifting, clipping and the file format, crumbling platforms
    included (the route leaves them out, as `check_reach` does);
  - the JS stitch against `compose.py` itself.
- `scripts/tools/room_jump_test.gd`: where a draft lies, and its backdrop rule.
- `tools/studio/e2e/studio.e2e.cjs`: the tab opens, traces, takes a ledge and
  undoes it.
