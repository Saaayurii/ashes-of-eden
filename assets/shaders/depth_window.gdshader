shader_type canvas_item;
render_mode unshaded;

// Polygon geometry is the hand-authored, stationary opening in the painting.
// Only the inpainted plate sampled behind it shifts with the camera.
uniform float shift_px = 0.0;
uniform float plate_width = 1600.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.82;

void fragment() {
	vec2 plate_uv = UV;
	plate_uv.x = clamp(plate_uv.x - shift_px / plate_width, 0.0, 1.0);
	vec4 painted = texture(TEXTURE, plate_uv);
	vec4 vertex_tint = COLOR;
	COLOR = vec4(painted.rgb * vertex_tint.rgb, painted.a * opacity * vertex_tint.a);
}
