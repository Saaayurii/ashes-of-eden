# Blind Preacher nave art v1

Generated with the built-in imagegen tool (not the CLI), then copied to
`assets/levels/preacher_nave_interior_v1.png` (2172 x 724). The original
generated image is retained; no existing bitmap was overwritten.

`scripts/rooms/interior_architecture.gd` loads this plate only for
`preacher_nave.tscn`, using the imported texture with a raw-image fallback.
It fits the room's 1200 x 420 bounds and stays stationary in world space.
Old repeating wallpaper, enlarged arches and columns are hidden rather than
stacked over the new architecture. Balcony supports and the existing animated
exit gate remain independent and floor-anchored. Floor/platform collisions,
boss markers, offerings and the preacher arrival scene are unchanged.

This iteration is one opaque architectural plate, not separately extracted
painted parallax planes. Window recesses provide painted depth; existing
behind-wall depth planes do not become visible through this opaque image.

## Verification

Godot import, the two-interior layout test, preacher arrival, all-room prop
footing (126 props / 111 decorations) and the 19-room depth checks pass.
The traversal bot reaches the exit and all 3 arena surfaces; it reports no
prop targets for this quiet arena, so this is not proof of prop interactions.
Its shutdown still reports 12 leaked ObjectDB instances / 6 resources in use.
Rendered overview and normal-zoom exit previews were inspected in Godot.

## Final generation prompt

Use case: stylized-concept
Asset type: production background-only panorama for a side-view dark fantasy pixel-art platformer, the Blind Preacher's nave boss room.
Primary request: paint a distinct abandoned Gothic Christian nave, cold and somber, harmonious with weathered blue-gray stone game platforms. Wide approximately 3:1 horizontal panorama, target 2400 by 800 pixels.
Composition: strict orthographic side elevation, camera perpendicular to the rear wall, no perspective floor. A continuous rear architectural wall with three broad recessed pointed-arch bays, a tall weathered central tracery window with a damaged simple cross motif, cracked narrow windows in the side bays. Delicate structural depth through recessed masonry and shadow, not foreground obstacles. Quiet readable center and lower quarter behind moving fighters. Place architectural buttresses between bays, not loose floating columns. At far right, about 97 percent across, a small dark recessed doorway in the wall behind the game's separate exit gate.
Style: carefully authored dark fantasy pixel art, discrete crisp pixels and restrained dithering, coherent stone sizes, muted blue slate, charcoal and desaturated violet. Worn mortar, hairline cracks, subtle mineral stains, broken glass limited to windows; abandoned church, not lava cave. Cool subdued moonlight filtering through the upper glazing, faint dusty air; gentle contrast so enemies and hero remain legible. No bright huge light beams.
Constraints: background only, opaque entire canvas, artwork reaches all edges. Bottom quarter must remain flat quiet dark wall shading, no distinct ledges or footholds. The real floor is added separately at 90 percent image height. No painted floor, no stairs, no platforms, no balconies, no furniture, no altar, no podium, no coffin, no characters, no statues, no foreground props, no floating blocks, no text, no labels, no UI, no watermark, no border. Do not show a deep perspective corridor or vanishing point. No white or empty canvas.
