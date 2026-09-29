shader_type canvas_item;
render_mode unshaded;

// Only the distant sample moves. Authored window geometry never distorts.
uniform float shift_px = 0.0;
uniform float plate_width = 1600.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.70;
uniform float heat_px : hint_range(0.0, 2.0) = 0.6;

void fragment() {
	vec2 plate_uv = UV;
	float heat = sin(UV.y * 80.0 + TIME * 0.8) * heat_px;
	plate_uv.x = clamp(plate_uv.x + (heat - shift_px) / plate_width, 0.0, 1.0);
	vec4 painted = texture(TEXTURE, plate_uv);
	vec4 vertex_tint = COLOR;
	COLOR = vec4(painted.rgb * vertex_tint.rgb, painted.a * opacity * vertex_tint.a);
}
