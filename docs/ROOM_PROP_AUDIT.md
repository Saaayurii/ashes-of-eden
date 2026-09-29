# Room prop footing audit

## Coverage

`scripts/tools/all_room_props_test.gd` instantiates every `.tscn` in
`scenes/rooms`, waits for physics registration, and checks:

- all 126 interactive props against world collision layers 1 and 5;
- the lowest visible pixel in every intact idle frame, including actual sprite
  scale, offset and transform;
- the resting strip's alignment;
- the feet of 111 floor decorations in `DecorMid` and `DecorFront`.

The 19 scenes are village_night; graveyard, graveyard_cross, graveyard_arches,
graveyard_tree; swamp_moon, swamp_red, swamp_crypt; catacombs_1, catacombs_2,
catacombs_3; crypt_skulls, crypt_lava; hell_gate; church, preacher_nave;
dead_bridge, fallen_knight, church_ophanim.

Background scenery (`DecorBack`), effects and objects painted into the room
panel are not physical props and are not covered by these floor rays. Passing
the audit is not proof that every collider matches the painted surface.

## Corrections

- `graveyard`: gold chest moved from an unsupported point to the upper ledge
  at (1130, 200). Barrels, stacked crates and sacks now use funeral offerings
  and rubble instead of village storage clutter.
- `catacombs_2`: the reliquary at (1550, 630), above a stair rather than its
  floor, moved to its own upper ledge at (1510, 481).
- `catacombs_3`: rubble beyond the end of a ledge moved from (1320, 583) to
  (1290, 583).
- `dead_bridge`: loose crates replaced with masonry rubble; bridge supplies
  such as its iron barrel remain.
- `fallen_knight`: ordinary storage props replaced with rubble and offerings.
- `church_ophanim`: pot, barrel and crate replaced with offerings and rubble;
  the entry offering moved away from Matthew and the next offering separated
  from its neighbour.

Scene placements and `tools/rooms/generate_rooms.py` agree. Chests, secrets
and their payout data are preserved.

## Animation

### Visual follow-up: catacombs_2, catacombs_3, crypt_skulls

Room renders revealed a case the original physics audit could not detect:
the reliquary at (760, 340) in crypt_skulls stood on a collider tracing a
distant scenic bridge, not on foreground masonry. It now stands on the real
gallery at (1210, 423); the background bridge collider is removed.

All four added stepping cornices in these three rooms now use 12-pixel stone
caps sampled from their own painting instead of oversized foreign platform
strips. The three redundant exit shrine sprites are removed; painted shrines,
exit doors and rewards remain. Scene edits are mirrored in the source tables.
The audit also guards against reintroducing these three statues, foreign
platform art and the scenic bridge's collision. Physics traversal still
reaches each room's door and all walker targets (27, 22 and 31 surfaces).

### Visual follow-up: crypt_lava and hell_gate

The expansion mapper previously omitted hazards: the paintings widened but
their lava rectangles stayed at original coordinates. Hazards now use the
same mapping as floors, including added width across seams. The lava crypt's
pool spans x=750..1470; the gate's three pools span 425..687, 801..1111 and
1310..1398. Removed both rooms' invisible bottom safety floors, extra exit
statues, and the gate's distant bridge/chain ledges. Removed the brazier
standing on that scenic bridge rather than moving it onto arbitrary masonry.

The gate's cursed chest moved from the isolated lower outcrop to (990, 482)
on the foreground bridge; the adjacent reliquary moved to (1060, 482) to
leave space. The chest and its payout are unchanged. The lower painted
outcrop retains its collider, but has no reward drawing the player into it.
All prop footings pass (126 props / 111 floor decorations). Traversal with
the optional `props` argument also checks prop surfaces, not just enemies
and exits: all targets pass in these two rooms. The bot does not find a
route to the now-empty lower outcrop; this is not a required gameplay target.

`lava_room_test.gd` exercises both edges of every pool with the real player,
checks damage and safe return, absence of phantom floor/bridge collision,
and fatal out-of-bounds falls even with extra lives. All checks and the
10-room stair test pass. Source-table hazard bounds match the edited scenes.

### Interior follow-up: church and preacher_nave

These two rooms used repeating ruined column strips as wallpaper. Their
room-specific `interior_architecture.gd` composition hides that wallpaper,
uses the intact brick portion of `wall_tiles.png`, and leaves three arched
openings for the existing depth planes. Existing art is reused; no generated
bitmap or gameplay collider is introduced. The church uses warm masonry and
the preacher's arena a cooler palette with separately positioned bays.

Columns now share one floor-anchored stone material. Wide balconies have
posts reaching the real floor; the animated exit gate has stone jambs rather
than a second gate or statue. Architectural arches no longer parallax away
from the floor. The two arena offerings moved to x=120 and x=1080, clear of
arrival and exit (generator source positions are 120 and 840 before widening).
Church NPC, bell, shrine, dialogue and boss arrival are unchanged.

`interior_layout_test.gd` checks these anchors, supports, material consistency,
story fixtures and clear entry/exit positions. Both rooms' exits and all their
platform surfaces pass the physics traversal bot; preacher arrival, global
prop footing and the 19-room depth-layer checks also pass.

The subsequent church art iteration replaces its procedural masonry/arches
with a new generated background plate, `church_interior_v1.png`. The preacher
arena now has its own cold, damaged-glazing nave background,
`preacher_nave_interior_v1.png`, rather than repeating the church composition.
Both plates hide the procedural wallpaper/arches/columns, keep physical floor
and balconies independent, and preserve interactive fixtures and arrivals.
See `CHURCH_ART_V1.md` and `PREACHER_NAVE_ART_V1.md` for the generation prompts,
loading behavior and the limits of these single-plate backgrounds.

Intact prop frames have independently measured transparent bottom padding.
Rigid objects no longer breathe, sway or bounce vertically while idle. World
impulses and light damage use a small horizontal reaction. Opening/breaking
restores the authored strip offset and removes any frozen kick, so remains
stay anchored even when destruction starts in the second idle frame.

## Verification commands

### Active hell_gate far-art iteration

The foreground painting and all physical surfaces are retained. A new
room-specific atmosphere plate replaces the sample only inside its three
existing background openings. UVs account for the generated PNG resolution,
each opening keeps its own bounded depth offset, and faint heat shimmer is
confined to the far sample. Generic column cutouts are hidden, not layered
over the new art. See `HELL_GATE_DEPTH_V2.md` for the prompt and test evidence.
The initial depth-art check reached 18/19 surfaces. A subsequent route pass
adds two wall-attached native-stone cornices to recover from the lower-right
island: all 21 surfaces are now reached forward and in reverse with mantling.
Without mantle, the return reaches the gate but not the highest left shelves.
See `HELL_GATE_RETURN.md`; lava bounds and prop placement remain unchanged.

### Standalone Ophanim sanctuary

`church_ophanim.tscn` now has a dedicated stationary sanctuary background,
`ophanim_sanctum_v1.png`, instead of the moving village plate. Outdoor decor,
old village lights and unrelated column cutouts are hidden; arena collisions,
five ledges, boss marker and story fixtures are preserved. Its art/geometry
regression test passes. This legacy standalone scene is not in the main run's
ROOMS array (the active Ophanim arena is `hell_gate`); no encounter ordering
was changed. See `OPHANIM_SANCTUM_ART_V1.md` for the prompt and preview command.

```sh
godot --headless --path . -s scripts/tools/all_room_props_test.gd
godot --headless --path . -s scripts/tools/prop_test.gd
godot --headless --path . -s scripts/tools/secret_test.gd
godot --headless --path . -s scripts/tools/first_rooms_geometry_test.gd
godot --headless --fixed-fps 60 --path . -s scripts/tools/reach_test.gd -- 'catacombs_2|catacombs_3'
godot --headless --fixed-fps 60 --path . -s scripts/tools/reach_test.gd -- 'crypt_lava|hell_gate' props
godot --headless --fixed-fps 60 --path . -s scripts/tools/lava_room_test.gd
godot --headless --path . -s scripts/tools/interior_layout_test.gd
```

All checks pass. The prop/reach harnesses still report ObjectDB/resource
cleanup warnings at shutdown; these are separate from the footing assertions.

## Hell gate left-return follow-up

Traced the upper left stair against the painting and corrected its lower
landing from y=254 to y=239, including the rubble and cross footing. Added
two native-stone return cornices at the left rock edge, with the upper lip
clearing the stair underside. Forward and reverse physics traversal reach
24/24 surfaces without mantling. Both stair landings can be crossed on foot
without jumping; ten-room stair regression passes. The full prop audit
still reports 126 props, 111 grounded decorations and zero failures.
Source generation tables mirror the scene without regenerating other rooms.
See `HELL_GATE_RETURN.md` for coordinates and commands.

## Hell gate cornice visual follow-up

All four return steps now use dedicated transparent stone-corbel artwork,
rather than thin rectangular painting crops. The supports taper beneath
the walkable edge; right-wall pieces mirror the left attachment. The room
painting and all collision positions remain unchanged. The old caps are
retained only as a missing-asset fallback. See `HELL_CORNICE_ART_V1.md` for
the saved asset, final prompt, integration and visual QA commands.

## Lava crypt architectural exit follow-up

Moved the exit from the statue-side point (1560,176) into the painted gate
at (1450,176). Replaced the flat collision through the upper right stairs
with a short landing and hand-traced stair. Both landings are walkable in
both directions without jumping, and forward traversal reaches all 27
surfaces. Props, artwork and lava geometry are unchanged. See
`CRYPT_LAVA_EXIT.md` for source coordinates, test scope and preview command.
