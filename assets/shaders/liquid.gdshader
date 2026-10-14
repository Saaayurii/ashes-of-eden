shader_type canvas_item;
// The body of a pool (scripts/rooms/liquid_surface.gd draws the polygon, its
// top edge the living surface). UV.x runs across the pool, UV.y from the
// highest the surface rises (0) to the bottom (1); `pool` is its size in px.
// Pixel-snapped on purpose: the room is pixel art. The studio's «Жидкости»
// preview ports this look: change one, change the other.

uniform vec4 surface_color : source_color = vec4(0.66, 0.82, 0.92, 1.0);
uniform vec4 body_color : source_color = vec4(0.12, 0.26, 0.37, 1.0);
uniform vec4 deep_color : source_color = vec4(0.04, 0.09, 0.15, 1.0);
uniform vec4 glow_color : source_color = vec4(0.5, 0.7, 0.88, 1.0);
uniform sampler2D body_texture : repeat_enable, filter_nearest;
uniform bool has_texture = false;
uniform vec2 pool = vec2(100.0, 30.0);
uniform float opacity = 0.66;
uniform float flow = 0.05;
uniform float shimmer = 0.3;
// lava: the texture's brightest pixels are cracks that glow and breathe
uniform float molten = 0.0;
// Settings.backdrop_motion (0 stills the wobble), Settings.flash_scale()
uniform float motion = 1.0;
uniform float light_scale = 1.0;
// what is still churning after a splash, 0..1 (the surface's own energy)
uniform float stir = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 px = floor(UV * pool);
	float depth = UV.y;
	// surface → body over the first few pixels, body → deep below
	vec3 col = mix(surface_color.rgb, body_color.rgb, smoothstep(0.0, 6.0 / max(pool.y, 6.0), depth));
	col = mix(col, deep_color.rgb, smoothstep(0.25, 1.0, depth));
	if (has_texture) {
		// the texture drifts with the flow and wobbles a pixel either way: refraction, cheaply
		float wob = floor(sin(px.y * 0.35 + TIME * 1.7) * 1.5 * motion + 0.5);
		vec2 tc = (px + vec2(TIME * flow * 64.0 * motion + wob, 0.0)) / 64.0;
		vec4 t = texture(body_texture, tc);
		float lum = dot(t.rgb, vec3(0.299, 0.587, 0.114));
		if (molten > 0.0) {
			// a second layer the other way, slower: the crust plates slide over each other
			vec4 t2 = texture(body_texture, (px * 0.5 + vec2(-TIME * flow * 20.0 * motion, 7.0)) / 64.0);
			float crack = smoothstep(0.55, 0.85, max(lum, dot(t2.rgb, vec3(0.333)) * 0.9));
			float breathe = 0.75 + 0.25 * sin(TIME * 1.3 + px.x * 0.045) * light_scale;
			col = mix(col * (0.55 + 0.45 * t.rgb), glow_color.rgb * 1.35, crack * breathe * molten);
		} else {
			col *= 0.72 + 0.56 * t.rgb;
		}
	}
	// glints just under the surface, more of them while it is stirred
	float band = 1.0 - smoothstep(0.0, 5.0 / max(pool.y, 5.0), depth);
	float g = step(1.0 - 0.06 * (shimmer + stir), hash(vec2(floor(px.x / 3.0), floor(TIME * 3.0 + px.x * 0.01))));
	col += glow_color.rgb * g * band * 0.6 * light_scale;
	COLOR = vec4(col, opacity * COLOR.a);
}
