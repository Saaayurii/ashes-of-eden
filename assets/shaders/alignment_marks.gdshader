shader_type canvas_item;
// What the three counters have done to the body, drawn on top of whatever
// frame is showing. It works off the sprite's own alpha rather than a painted
// mask, so it costs no art and survives every animation the hero has.
//
//   grace       light gathering along the edge of him, steady
//   temptation  veins under the skin, filling and emptying with a pulse
//   will        ash settling on him: colour draining, grit catching the light
//
// `strength` is the same 0..1 lean Player._update_aura computes for the aura,
// so the two never disagree. At 0 this shader is a no-op and can stay bound.
uniform int mode : hint_range(0, 2) = 2;   // 0 grace, 1 temptation, 2 will
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.88, 0.5, 1.0);
// The frame is one cell of a sheet, so UV does not run 0..1 across the body.
// Sampling neighbours needs the real texel size, which Godot hands us.
uniform float rim_width = 1.4;
// The skin (data/skins): the red of his cloak and hood carried to another
// colour, and the rest of him tinted. No mask: the cloak is the only strongly
// saturated red on the sheet, so a hue window finds it in every frame.
uniform bool skin_on = false;
uniform float cloak_hue = 0.0;
uniform float cloak_saturation = 1.0;
uniform float cloak_value = 1.0;
uniform vec4 armor_tint : source_color = vec4(1.0);

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 skin(vec3 rgb) {
	vec3 hsv = rgb2hsv(rgb);
	float red = max(smoothstep(0.07, 0.03, hsv.x), smoothstep(0.90, 0.95, hsv.x));
	float cloak = red * smoothstep(0.28, 0.45, hsv.y);
	vec3 dyed = hsv2rgb(vec3(cloak_hue, clamp(hsv.y * cloak_saturation, 0.0, 1.0),
		clamp(hsv.z * cloak_value, 0.0, 1.0)));
	return mix(rgb * armor_tint.rgb, dyed, cloak);
}

// Cheap value noise. No texture to load, and the body is small enough on
// screen that nobody will read the lattice.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (skin_on && base.a >= 0.01) {
		base.rgb = skin(base.rgb);
	}
	if (base.a < 0.01 || strength <= 0.0) {
		COLOR = base;
	} else {
		vec3 rgb = base.rgb;
		// Built-in TEXTURE must be sampled inside fragment() in Godot 4.7;
		// passing it to a helper's sampler argument fails shader compilation.
		float rim = 0.0;
		if (mode != 2) {
			vec2 step_uv = TEXTURE_PIXEL_SIZE * rim_width;
			float around =
				texture(TEXTURE, UV + vec2(step_uv.x, 0.0)).a +
				texture(TEXTURE, UV - vec2(step_uv.x, 0.0)).a +
				texture(TEXTURE, UV + vec2(0.0, step_uv.y)).a +
				texture(TEXTURE, UV - vec2(0.0, step_uv.y)).a;
			rim = clamp(1.0 - around * 0.25, 0.0, 1.0);
		}
		if (mode == 0) {
			// Light along the edge, brightest where the body ends. Steady on
			// purpose: grace in this game is certainty, and certainty does not
			// flicker.
			float breath = 0.88 + 0.12 * sin(TIME * 1.1);
			rgb = mix(rgb, tint.rgb, clamp(rim * strength * breath, 0.0, 0.85));
		} else if (mode == 1) {
			// Veins: thin threads of noise under the skin, filling and
			// emptying at about the rate of a heart that is working too hard.
			vec2 p = UV / max(TEXTURE_PIXEL_SIZE, vec2(0.0001)) * 0.18;
			float threads = noise(p + vec2(0.0, TIME * 0.35));
			threads = smoothstep(0.62, 0.78, threads);
			// Away from the edge: veins run under a body, not around it.
			float inside = 1.0 - rim;
			float pulse = 0.55 + 0.45 * sin(TIME * 2.6);
			rgb = mix(rgb, tint.rgb, clamp(threads * inside * strength * pulse, 0.0, 0.8));
		} else {
			// Ash: the colour goes out of him and a grit of it catches the
			// light. The path that takes neither side is the one that fades.
			float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
			rgb = mix(rgb, vec3(grey), strength * 0.55);
			vec2 p = UV / max(TEXTURE_PIXEL_SIZE, vec2(0.0001)) * 0.5;
			float grit = step(0.93, noise(p + vec2(TIME * 0.05, TIME * 0.11)));
			rgb = mix(rgb, tint.rgb, grit * strength * 0.5);
		}
		COLOR = vec4(rgb, base.a);
	}
}
