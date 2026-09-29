# Hell gate distant atmosphere v2

This iteration affects the active run's `hell_gate` room. The foreground
`hell_gate_wide.png`, collision geometry, stairs, door, lava bounds,
props, boss marker and story references remain unchanged.

The built-in imagegen tool edited
`assets/levels/depth/hell_gate_backfill_wide.png` into a separate
`assets/levels/depth/hell_gate_atmosphere_v2.png` (1870 x 841).
Original assets were not overwritten. The first request failed with a
connection error; the built-in retry succeeded. No CLI fallback was used.

`hell_depth.gd` binds the new texture only inside the three existing
feathered polygon groups. UV coordinates are rescaled to the actual generated
resolution, so sampling still corresponds to the 1600 x 720 room coordinates.
Window boundaries and vertex alpha masks are preserved exactly. Each window
retains its separate camera-depth factor and a maximum shift of 16 room pixels.

The room-specific shader adds slow, subpixel heat shimmer (0.6 room pixels)
only to the far sample, never to window geometry or the foreground. Opacity
is 0.70; generic cutout columns are hidden for this room. This is a targeted
far-layer refinement, not a replacement of the whole room picture or an
extraction of all foreground objects.

## Verification

- Godot overview and normal-zoom previews inspected.
- `hell_depth_art_test.gd` passes: unchanged masks/colliders, resolution-aware
  UVs, separate bounded shifts while moving the camera, foreground preserved.
- `lava_room_test.gd` passes, including pool edges and fatal outside falls.
- Reach bot reaches the door and 4 targets, 18 of 19 surfaces (42 hops).
  At that iteration the empty bottom-right island was unreachable. The
  subsequent route repair in `HELL_GATE_RETURN.md` joins it to the right
  wall and verifies all 21 surfaces in both directions with mantling.
- All-room prop footing: 126 props / 111 decorations / 0 failures.
- 19-room depth structure check passes.
- Reach/lava harness shutdown still reports ObjectDB/resource cleanup warnings.

## Final edit prompt

Use case: lighting-weather
Input images: Image 1 is the edit target, the existing full-width distant background plate for a hell gate game room.
Primary request: refine this distant Gothic volcanic chasm background to read as a deeper scenic layer, not playable foreground. Keep the exact composition and locations of every large bridge, mountain silhouette and lava waterfall, framing and aspect ratio 1600:720. Only change atmospheric depth, light and fine surface treatment.
Style: preserve dark fantasy crisp pixel-art style, burgundy charcoal stone, burning orange lava. Bring subtle warm smoky atmospheric haze across distant architecture, lower small-detail contrast slightly, make bridge tops less sharp than foreground platforms would be, restrain the white-hot highlights. Keep coherent aged Gothic masonry and natural glowing lava streams. A muted distant landscape, not washed-out grey or blurry.
Constraints: retain all major outlines and their exact positions. No new bridges, floors, stairs, near rocks, statues, creatures, props, lettering or UI. No foreground, no added floating objects, no rearrangement of the level. Same wide canvas, opaque edge-to-edge image. This plate will be shown ONLY through three small fixed polygon openings; matching existing structures at the edges is crucial. Do not darken into black patches; preserve overall orange ambient value and original geometry.
