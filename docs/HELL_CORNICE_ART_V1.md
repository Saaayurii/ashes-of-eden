# Hell return cornice artwork v1

Generated with the built-in image generation tool (not the CLI).
Saved asset: `assets/levels/depth/hell_cornice_v1.png`, RGBA, 2172 x 724.
The generated alpha is preserved; the source file is copied without raster
editing. Existing room paintings are not overwritten.

The reference is `assets/levels/hell_gate_wide.png` (style only). The sprite
adds a stone corbel beneath each of the four existing return cornices.
`scripts/rooms/hell_cornice.gd` selects Rect2(215,112,1914,545), excluding
the tall attachment column and padding, and scales uniformly to the authored
walkable width. Right-wall pieces are mirrored. Artwork extends below the
walkable top and has no collision, so it cannot close routes underneath.
The existing top positions and one-way collision shapes are unchanged.
If the new asset is unavailable, the original painted cap remains visible.

The room generator also selects this artwork for hell_gate only. It was not
run over the edited scene collection. No dialogue or translation keys change.

## Final prompt

```text
Use case: stylized-concept. Asset type: transparent 2D game environment sprite, one stone cantilever corbel for a side-view platformer. Input image: hell_gate_wide.png is STYLE REFERENCE ONLY, do not redraw the room. Generate ONE isolated gothic dark basalt architectural ledge supported underneath by a thick weathered triangular masonry corbel: vertical attachment on LEFT, level walkable top projects to RIGHT, underside tapers upward toward the right tip. Pure side elevation orthographic, absolutely horizontal straight top edge, no visible top perspective plane. Wide low silhouette about 3:1 width to height; full object visible with small transparent padding. Match reference's dark brown charcoal stone, subtle warm ember reflected highlights, restrained cream stone-edge highlight, pixel-art-like hand-painted texture readable when reduced to 125 by 42 game pixels. Stone blocks irregular but structurally coherent, chipped right tip. Actual transparent background and alpha, no checkerboard, no cast shadow outside object, no lava, no plants, no statues, no chains, no writing, no glow effects, no extra objects. This is a wall-attached stone support, not a floating island or standalone column.
```

## Verification

Native-scale Godot previews inspected from both sides of the room. The left
stair walk and art-width regression passes. Forward and reverse traversal
still reaches 24/24 surfaces without third-press mantling. Lava bounds and
fall-death checks remain in lava_room_test.gd; cleanup warnings at test exit
are separate from the assertions.

```sh
godot --path . -s scripts/tools/depth_preview.gd -- hell_gate 390 345 /tmp/hell-corbel-left-final.png
godot --path . -s scripts/tools/depth_preview.gd -- hell_gate 1280 490 /tmp/hell-corbel-right.png
godot --headless --fixed-fps 60 --path . -s scripts/tools/hell_left_stairs_test.gd
godot --headless --fixed-fps 60 --path . -s scripts/tools/reach_test.gd -- hell_gate props reverse no_mantle all_surfaces
godot --headless --fixed-fps 60 --path . -s scripts/tools/lava_room_test.gd
```
