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
    "ramps": [[x0, y0, x1, y1]], "hazards": [[x, y, w, h]],
    "player": [x, y], "door": [x, y],
    "spawns": [[id, x, y]], "props": [[id, x, y]], "npcs": [[id, x, y]]}}
```

- **Cells.** A grid of at most 6×4. Cell (col, row) starts at (col·1280, row·720).
  Every painting must be 1280×720. A painting is either one the game already has
  (`assets/levels/<stem>.png`) or a new one the studio uploads
  (`assets/levels/panels/<stem>.png`, fitted to the cell, cropped from the
  centre). A hole in the grid is filled with night: the darkest tenth of the
  paintings, stitched like any other neighbour. Fill it, or keep the walk away
  from it.
- **Coordinates** are in the finished room's pixels, not panel pixels.
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

See `compose._join`. Each side is carried past the seam by its own mirror, so
both pictures cover the same 2×96 px band. A min-cost path runs through the
middle half of the band, where the two agree best. Each side bends its light
halfway toward the other's, fading out toward its own edge, so the pictures stay
exact beyond the band and a change of light is spread across it rather than
drawn as a line. A row of cells is joined first, then the rows are joined
top to bottom the same way (transposed).

Candles come from each panel's own `.lights.json`, or from the tracer for a new
painting, moved into their cell. A composed room has no depth windows and no
parallax plates: its picture is drawn whole. Its backdrop life is its room's
flames with no zones (`BackdropLife.rule("composed/<name>")`), because the
zones were drawn on another picture. Give it zones of its own in
`data/backdrops.json` under that key.

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
  - Draw new ground, ledges, platforms, ramps and hazards with the tools.
  - Place enemies and things, and change their kind in the side panel.
  - Delete removes the selection, Ctrl+Z undoes, the wheel zooms, and the right
    button or Space pans.
- **The hero's route** is checked as you edit (`composeReach`, a port of
  `painted_rooms.check_reach`). The panel lists what cannot be reached, marks it
  on the picture, and greys out surfaces off the route.
- **«→ В игру»** writes the table and any new paintings:
  - Locally, the server regenerates the rooms and runs the validator.
  - Online, it opens a pull request, and the studio robot regenerates the rooms
    on it.

  A live room whose route does not hold is refused.

## Tests

- `tools/studio/tests/test_compose.py`: the stitch keeps both pictures exact
  away from the seam, bad entries are refused, and the room table is the grid.
- `tools/studio/tests/lib.test.js`: reach, tracer, shifting, clipping and the
  file format.
- `scripts/tools/room_jump_test.gd`: where a draft lies, and its backdrop rule.
- `tools/studio/e2e/studio.e2e.cjs`: the tab opens, traces, takes a ledge and
  undoes it.
