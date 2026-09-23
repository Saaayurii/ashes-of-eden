shader_type canvas_item;
uniform float phase = 0.0;
uniform int motion_kind = 0;
uniform bool use_frames = false;

// A small edge shimmer, not a circular glow: the painted silhouette remains
// readable while its trailing wisps breathe in flight.
void fragment() {
	vec2 uv = UV;
	float motion = phase * 16.0;
	if (use_frames) {
		// Frame atlases are already animated; never sample over a cell edge.
		uv = UV;
	} else if (motion_kind == 1) {
		uv.y += sin(motion + uv.x * 19.0) * 0.012 * (1.0 - uv.x);
	} else if (motion_kind == 2) {
		uv.y += sin(motion + uv.x * 23.0) * 0.026 * (1.0 - uv.x);
		uv.x += sin(motion * 0.73 + uv.y * 25.0) * 0.011;
	} else if (motion_kind == 3) {
		uv.x += sin(motion * 1.7 + uv.y * 29.0) * 0.012 * (1.0 - uv.x);
	} else if (motion_kind == 4) {
		uv.y += sin(motion + uv.x * 21.0) * 0.005;
	} else {
		uv.x += sin(motion + uv.y * 19.0) * 0.006 * (1.0 - uv.x);
	}
	vec4 painted = texture(TEXTURE, uv);
	float shimmer = 0.87 + 0.13 * sin(phase * 23.0 + uv.x * 13.0);
	COLOR = vec4(painted.rgb * shimmer, painted.a);
}
