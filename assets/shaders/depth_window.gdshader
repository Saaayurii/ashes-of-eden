shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/backdrop_life.gdshaderinc"

// Polygon geometry is the hand-authored, stationary opening in the painting.
// Only the inpainted plate sampled behind it shifts with the camera.
uniform float shift_px = 0.0;
uniform float plate_width = 1600.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.82;

void fragment() {
	vec2 plate_uv = UV;
	plate_uv.x = clamp(plate_uv.x - shift_px / plate_width, 0.0, 1.0);
	// the same life as the painting around the opening (backdrop_life.gdshaderinc)
	vec2 px = plate_uv / TEXTURE_PIXEL_SIZE;
	Life l = life_gather(px, TIME);
	vec4 painted = texture(TEXTURE, plate_uv + l.offset * TEXTURE_PIXEL_SIZE);
	vec4 wet = l.wet > 0.0 ? texture(TEXTURE, plate_uv + (l.offset + l.ripple) * TEXTURE_PIXEL_SIZE) : painted;
	vec4 hot = l.molten > 0.0 ? texture(TEXTURE, plate_uv + (l.offset + l.melt) * TEXTURE_PIXEL_SIZE) : painted;
	painted = life_finish(painted, wet, hot, l, px, TIME);
	vec4 vertex_tint = COLOR;
	COLOR = vec4(painted.rgb * vertex_tint.rgb, painted.a * opacity * vertex_tint.a);
}
