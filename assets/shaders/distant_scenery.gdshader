shader_type canvas_item;
render_mode unshaded;

// Distant cutouts keep their painted outline but disappear into the lower haze.
// They are atmosphere, never a second foreground platform or a solid object.
void fragment() {
	vec4 art = texture(TEXTURE, UV);
	float lower_haze = 1.0 - smoothstep(0.52, 1.0, UV.y);
	COLOR = vec4(art.rgb * COLOR.rgb, art.a * COLOR.a * lower_haze);
}
