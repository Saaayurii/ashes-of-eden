# Hell gate return routes and left stair

The isolated ledge at x=1400..1470, y=633 was a dead end: the nearest upper
ledge was 208 pixels above it. Two small one-way stone cornices now join
the right wall at (1525,563,75,12) and (1550,493,50,12). The climbs are
70, 70 and 68 pixels, rather than one impossible leap.

The original visible caps used this room's own painted stone bridge surface,
cropped at (800,482), not foreign mossy platform sprites or lava shelves.
The visual follow-up replaces those thin crops with dedicated transparent
stone corbels while retaining the old crops as an asset-loading fallback;
see `HELL_CORNICE_ART_V1.md` for the asset, crop and generation prompt.
Each visible top matches its collider and both cornices end at the right
room boundary. They do not add rewards, NPCs, floating props or solid
obstacles underneath the one-way tops. Existing lava bounds stay unchanged.

The positions and art crop are also in generate_rooms.py's expansion data.
The room generator was not rerun over the existing edited scenes.

## Verification

The follow-up also repairs the entrance-side climb. Two one-way cornices at
(225,405,65,12) and (265,315,125,12) join the left rock edge. The upper lip
extends beyond the solid stair underside, so the hero can jump onto the
upper landing instead of hitting its ceiling. Both use the same native
stone-corbel artwork as the right route, with no props or rewards added.

The upper left stair is traced at its actual painted treads from (270,176)
to (364,239). Its adjacent flat colliders now stop at the stair boundaries;
the lower landing is at y=239, not y=254 inside the painted masonry. The
rubble and cross on that landing move up by the same 15 pixels. Explicit
tread coordinates are supported in the generator; other rooms retain their
existing generated stairs.

Forward and reverse traversal from the lower island now reach all 24
surfaces, including the gate and entrance, without third-press mantling.
The dedicated left-stair test walks across both landings uphill and downhill
without jumping and checks visible cornice / collision matching. The
existing stair regression also passes in all ten rooms.

```sh
godot --headless --fixed-fps 60 --path . -s scripts/tools/reach_test.gd -- hell_gate props reverse no_mantle all_surfaces
godot --headless --fixed-fps 60 --path . -s scripts/tools/hell_left_stairs_test.gd
godot --headless --fixed-fps 60 --path . -s scripts/tools/stairs_test.gd
godot --headless --fixed-fps 60 --path . -s scripts/tools/lava_room_test.gd
godot --headless --path . -s scripts/tools/hell_depth_art_test.gd
godot --headless --path . -s scripts/tools/all_room_props_test.gd
```

The lava test additionally checks visible art / collision matching and the
wall attachment of both return cornices. Source-table positions are checked
by importing the generator without invoking build. Native-scale Godot
previews were inspected. Traversal/lava harnesses retain shutdown cleanup
warnings about ObjectDB instances and resources.
