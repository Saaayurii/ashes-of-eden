# Depth: three planes in a side view

A side view feels deep when the eye can tell three distances apart while the
camera moves:

- **far**: slower than the camera. It sits behind the painting's openings.
- **middle**: the painting and everyone who stands on it. It is fixed to the world.
- **front**: things nearer than the hero, moving faster than the camera. They are
  dark, a little soft, and they pass between the eye and the fight.

A painted room has had the first two for a while. This page is about the third,
and about how a room built in the studio's «Конструктор» gets all three.

## The far plane (openings)

`RoomLayers` and `Room` handle it.

- Every opening of a painting through which the distance shows (`DEPTH_WINDOWS`
  in the generator, `FAR_WINDOWS` in `room_layers.gd`) is a `DepthWindows`
  polygon.
- That polygon shows the room's inpainted plate (`assets/levels/depth/`) shifted by
  `min(max(0, camera_left) · depth_parallax · depth, 16)` px.
- The depth comes from the opening's number. The sky (1) is the farthest.
- A composed room also lists each opening's depth (`window_depths`) and which
  openings are sky (`sky_windows`). Clouds are clipped to every sky opening, not
  only the first.

## The front plane

`FrontLayer`, `scripts/rooms/front_layer.gd`, z 3: above the bodies and below the
effects.

- A piece is a `Sprite2D` baked by `tools/rooms/front.py` from a picture the game
  already has. There are no stock cutouts.
- How a piece is baked:
  - A crop is keyed: `dark` keeps what is darker than `cut`, `alpha` keeps a
    transparent PNG's own shape.
  - It is darkened by `dark`, mirrored by `flip` and scaled by its `depth`.
  - It is softened by `blur`, which defaults from `depth`.
  - Its edges are faded by `feather`, so the crop never reads as a box.
- At depth `d` its centre lies at `rest + (rest − camera) · (d − 1)`
  (`FrontLayer.at`, the Parallax2D rule). `rest` is where it stands when the camera
  looks straight at it.
- It takes no light (`light_mask` 0), because it stands between the lamps and the
  eye.
- A body behind a piece makes it fade to `FADED`, so the plane never hides a blow.
- Settings → Moving backdrops off holds every piece still.
- At most `front.MAX_PIECES` per room. `depth` is within `front.DEPTH` (1.05–1.8).

### Where the pieces come from

- **A painted room:** `tools/rooms/front_layers.json`, `{room: [piece, …]}` in the
  finished room's pixels. The crop is usually taken from the room's own
  `<room>_wide` picture.
- **A composed room:** `front` in its entry in `tools/rooms/composed_rooms.json`,
  drawn in the studio.

The baked pictures go to `assets/levels/front/<room>_<i>.png`, and
`composed_<room>_<i>.png` for a composed room. The generator owns them: regenerate,
don't hand-edit.

### What works

- A dark key only reads against something lighter. A silhouette laid over the
  painting's dark lower half disappears.
- What reads:
  - bare trees and columns crossing the fog;
  - branches and chains hanging in the sky;
  - a fence against the mist.
- Pick a `cut` that keeps the shape and drops the background. Try 40–60 on these
  paintings.
- A piece below the camera's focus slides further down as the camera rises. Place
  it so that it shows where the hero usually stands. For a wanted centre `c` at a
  usual focus `f`: `rest = (c + f · (d − 1)) / d`.
- Look at it with `scripts/tools/depth_shot.gd` (it needs a display):

  ```
  godot --path . -s scripts/tools/depth_shot.gd -- <out> res://scenes/rooms/<room>.tscn <camera y>
  ```

## In the studio

«Конструктор» → **◫ Объём** shows the room as the game's camera sees it, and the
mouse is the camera:

- the plate slides in the openings;
- the front pieces run ahead;
- the rest of the room is dimmed.

What you can do there:

- **+ Окно**: draw an opening onto the far plate. Drag it whole or by a corner.
  Set its depth and whether it is sky.
- **+ Передний план**: drag a frame over a painting. That piece is cut and stands
  where it was, keeping its foot. A piece hanging from the top keeps its top.
- **✨ Найти передний план**: offers dark masses along each painting's edges,
  starting below the walk. These are cyan frames; click one to take it.
- **🖼 Своя спереди**: a transparent PNG of your own, written to
  `assets/levels/pieces/`.
- **+ Свеча**: a light.
- The side panel edits depth, darkness, cut, edge fade, blur, mirror and key.

Until one of the layers is touched, the room keeps its cells' own: each cell
room's far openings and its candles. The first edit writes them all into the
entry, and «↺ Слои как у клеток» gives them back.

## Tests

- `scripts/tools/depth_test.gd`: where a piece stands as the camera moves, the fade
  behind it, and the motion setting.
- `scripts/tools/layers_test.gd`: the Front node's place in the draw order, its
  lights and depths, and the sky clip of a composed room.
- `tools/studio/tests/test_compose.py`: `Front`, `Windows`.
- `tools/studio/tests/lib.test.js`: `frontAt`, `frontEdgeFade` (= `front.edge_fade`),
  `frontCandidates`, `composeWindows`.
