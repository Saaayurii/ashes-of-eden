# Church interior v1

Generated with the built-in imagegen tool, then copied non-destructively to
`assets/levels/church_interior_v1.png` (2200 x 715). Consumed by
`scripts/rooms/interior_architecture.gd` only in `church.tscn`. Imported texture
loading supports exports; a raw image fallback supports a stale import cache.

This is a single stationary architectural background plate, not yet separated
into painted parallax layers. Existing floor, balconies, supports, exit gate,
NPC, bell and interactive shrine remain independent. Enlarged procedural
arches/columns are hidden for this room to prevent double-drawing.

## Final generation prompt

Use case: stylized-concept. Asset type: production background plate for a dark
gothic pixel-art 2D side-scrolling game, NOT concept-art mockup. Generate a NEW
church interior background, a very wide panoramic canvas about 3.15:1 (target
2400x760). Scene: a quiet ancient Christian stone church, worn dark blue-grey
masonry, coherent tall vaulted bays, restrained warm candles in wall niches,
distant amber stained glass with subtle cross motifs and cooler recessed side
aisles. Style: detailed crisp small-scale pixel art, dark realistic handcrafted
stone like a gothic cemetery platformer, controlled clusters and readable
silhouettes; no smooth blurry enlarged sprite look. View: strictly straight-on
side elevation, orthographic, no perspective floor receding into the screen.
Composition: the lowest 20% must stay dark, visually quiet and unobstructed for
moving characters and foreground gameplay props. The background has NO
playable floor, NO platforms, NO stairs, NO foreground pillars, NO furniture,
NO altar, NO characters, NO priest, NO statues, NO floating objects. These will
be added separately by the game at exact collision positions. Use three broad
architectural bays across the panorama, the central bay a slightly warm
illuminated apse, side bays cooler and recessed; asymmetrical age details
without copy-pasted repeating tiles. A modest dark recessed wall doorway near
the far right (97% width), its bottom meeting the image bottom, allows the
game's gate to overlay it. No lettering, no interface, no borders, no labels,
no watermark. Opaque background. This is background-only art, not a screenshot
and not a layout redesign. Keep contrast on the lower wall soft so existing
game sprites remain readable.
