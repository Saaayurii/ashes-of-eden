# Lava crypt exit and upper stair

The exit marker was at (1560,176), to the right of the painting's gate near
the statue. Its flat one-way shelf continued through the painted stair to
the room boundary, putting physical feet inside the ascending stonework.

The exit now sits inside the architectural gate at (1450,176). The one-way
landing is x=1417..1466, y=208; a separately traced solid stair rises from
(1460,208) to (1600,108). Tall painted risers have small intermediate collision
treads to remain walkable with the existing 12 px step-up, without changing
global player movement. The thin collision strip leaves routes below open.

This exit change added no props, statues, dialogue or translation strings.
The original painting and lava bounds are unchanged.
The scene and generation source both retain these authored coordinates;
other scenes were not regenerated.

## Verification

The exit-stair test crosses both landings on foot in both directions without
jumping. Traversal reaches 27/27 surfaces including all prop surfaces and
the new stair. This is forward exploration from the entrance, not a reverse
traversal claim. The waiting-at-door test also covers crypt_lava, so unlocking
while standing inside the arch triggers once. Lava / fatal-fall tests pass.
The full room prop audit remains 126 props / 111 grounded decorations with
zero failures. Headless tests retain shutdown resource-cleanup warnings.

## Return from the lower treasure terrace

The new reverse-start probe at (660,655) exposed a one-way dead end: only
5/27 surfaces were reachable, even with mantling available. Two one-way
stone cornices now connect the terrace to the middle shelf and the middle
walkway to the upper gallery: (730,610,100,12) and (700,315,85,12).
Visible tops exactly match the collider rectangles. Native stone from
(860,458) is reused, with decorative textured supports reaching into the
lower terrace / left cliff instead of leaving unsupported rectangular caps.
Supports add no collision. No rewards or props move.

Forward and reverse exploration now reach 29/29 surfaces without third-press
mantling. Cornice and support data are mirrored in the generator, which was
not run over other rooms. The exit-stair test additionally checks the two
cornices' visible top / one-way collision matching.

```sh
godot --headless --fixed-fps 60 --path . -s scripts/tools/reach_test.gd -- crypt_lava props reverse no_mantle all_surfaces
```

```sh
godot --headless --fixed-fps 60 --path . -s scripts/tools/crypt_lava_exit_test.gd
godot --path . -s scripts/tools/crypt_lava_exit_test.gd -- /tmp/crypt-lava-exit-player.png
godot --headless --fixed-fps 60 --path . -s scripts/tools/reach_test.gd -- crypt_lava props no_mantle all_surfaces
godot --headless --fixed-fps 60 --path . -s scripts/tools/door_waiting_test.gd
godot --headless --fixed-fps 60 --path . -s scripts/tools/lava_room_test.gd
godot --headless --path . -s scripts/tools/all_room_props_test.gd
```
