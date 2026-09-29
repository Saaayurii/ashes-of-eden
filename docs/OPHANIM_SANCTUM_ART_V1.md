# Ophanim sanctuary art v1

Generated using the built-in imagegen tool, not the CLI. Copied without
overwriting existing images to `assets/levels/ophanim_sanctum_v1.png`
(2048 x 768). Original generation retained.

Used by `interior_architecture.gd` for `church_ophanim.tscn` only. The
imported texture replaces the village backdrop and is fitted to 960 x 360.
A raw-image fallback is available for a stale import cache. The wall has
scroll scale (1, 1), not the previous camera-following village parallax.

Outdoor trees, cemetery ornaments, fences, grass and unrelated cutout
columns are hidden, not deleted. Old village-mounted lights are hidden.
Fog density is reduced to 0.06 with a duplicated per-room material.
Five combat ledges, floor collisions, NPC, shrine, props, barriers, boss
marker and arrival/finale references are untouched.

This is one opaque stationary plate, not extracted moving background layers.
The scene is NOT in the current main run's ROOMS array; the active Ophanim
fight is in hell_gate. No room ordering or encounter was changed. To view
this standalone sanctuary, open church_ophanim.tscn directly or use the
preview command below.

## Verification

`ophanim_room_art_test.gd`, `interior_layout_test.gd`, the 19-room depth
check and prop footing checks (126 props / 111 decorations) pass.
Overview rendering was inspected in Godot. The existing reach harness
does not enumerate this standalone room; its filtered PASS with no room
result is not evidence of arena traversal.

```sh
godot --path . -s scripts/tools/depth_preview.gd -- church_ophanim 480 180 /tmp/ophanim-after.png 0.67
godot --headless --path . -s scripts/tools/ophanim_room_art_test.gd
```
## Final generation prompt

Use case: stylized-concept
Asset type: production background-only pixel-art panorama for the Ophanim boss arena in a Gothic Christian side-scrolling game.
Primary request: a distinct high vaulted cathedral sanctuary rear wall, pale weathered limestone and blue-charcoal recesses with muted antique gold stained glass. Wide 8:3 horizontal canvas, target 1920x720.
Composition: strictly orthographic side elevation, perpendicular to the rear wall, no perspective floor or receding corridor. One monumental central circular rose window integrated into a pointed apse, restrained concentric tracery suggesting wheels without depicting a creature; two smaller recessed side chapels. A quiet darker wall plinth across the bottom quarter for readable game actors. A modest dark recessed doorway at 96 percent width meets the bottom of the canvas. Architectural columns integral to the rear wall, coherent scale and continuous masonry, not floating.
Style: detailed crisp dark-fantasy pixel art, controlled pixel clusters, discrete pixels, worn stone joints and small cracks, authentic Gothic ornament without excessive noise. Soft ivory-gold illumination limited to central upper glazing, cool blue shadow in side bays. Dark lower combat lane; restrained contrast so a flying boss remains readable against the upper wall.
Constraints: opaque background only, edge to edge. No painted playable floor, stairs, platforms, balconies, podium, furniture, altar, statues, trees, graveyard fences, tombstones, props, characters or boss. Actual floor is drawn separately by the game at 89 percent image height and five combat ledges separately at 44-69 percent image height. Do not draw extra ledges or footing. No text, no UI, no watermark, no border. No deep perspective, no white empty canvas.
