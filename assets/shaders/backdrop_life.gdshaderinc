// The life of a painted backdrop (scripts/rooms/backdrop_life.gd, data/backdrops.json).
// Shared by the painting and by its depth windows, so a waterfall that runs
// behind an opening runs on both sides of the frame in step.
//
// One rule for every room: every candle, lantern and torch the artist painted
// flickers by itself — a warm, bright pixel is a flame, no mask, no list.
// Then each room adds zones (rects in painting pixels) of a few kinds:
//   0 falls   water running down       4 lava    molten flow, breathing heat
//   1 water   ripples and glints       5 haze    heat shimmer over a fire
//   2 sway    banner/moss/cage/tree    6 stars   a night sky's twinkle
//   3 glow    a moon, a window, a gate 7 pulse   veins beating like a heart
// Everything fades out over the zone's edge, so the static painting around it
// never shows a seam. Displacements stay at a pixel or two: the picture is
// the level, and nothing may look like it moved off its collider.

const int LIFE_ZONES = 24; // BackdropLife.MAX_ZONES
uniform vec4 life_rect[LIFE_ZONES];   // x, y, w, h in painting pixels
uniform vec4 life_shape[LIFE_ZONES];  // kind, strength, speed, extra (sway: 0 hangs, 1 stands; water: how bright water is)
uniform vec4 life_tint[LIFE_ZONES];   // glow colour
uniform int life_count = 0;
// Which zones touch each LIFE_CELL x LIFE_CELL block of the painting: a bit
// per zone, bits 0-7 in red, 8-15 in green, 16-23 in blue (BackdropLife
// builds it). A pixel reads its block and visits only those zones — testing
// all of them at every pixel cost ten times a plain sprite (backdrop_life_bench.gd).
uniform sampler2D life_cells : filter_nearest;
const float LIFE_CELL = 16.0;
uniform float life_flame = 0.0;       // candle flicker strength
uniform float life_flame_floor = 0.55; // brightness from which a warm pixel is a flame
uniform float life_light = 1.0;       // Settings.flash_scale(): how far light may change
uniform float life_motion = 1.0;      // 0 stills every displacement
// The place answers the hero (Ambience feeds both, BackdropLife.react): a gust
// from a dash, a landing, a parry or a death — origin in painting pixels,
// energy, sideways push — swings what hangs near it and stirs the water; a
// room cleared lets the light swell for a moment.
uniform vec4 life_wind = vec4(0.0);   // x, y, energy, push (-1 left … 1 right)
uniform float life_exhale = 0.0;      // 0..1 after a room is cleared
uniform float life_flash = 0.0;       // lightning or a scene's flash: the sky and the cold stone light up
uniform vec3 life_flash_tint = vec3(0.7, 0.78, 1.0);
// A boss fight heats the place: 0 at its first blow, near 1 as it falls —
// glows, lava, haze, flames and veins all burn harder.
uniform float life_rage = 0.0;
// The path the hero leans to (Game.dominant_path) colours every painted
// flame: rgb from data/backdrops.json "lean", a = how far he leans.
uniform vec4 life_lean = vec4(1.0, 1.0, 1.0, 0.0);
uniform float life_dread = 0.0;       // 0..1 as our own body nears death: the veins beat harder
uniform float life_beat_clock = -1.0; // the heartbeat's own clock (it quickens); < 0 = TIME
const float LIFE_GUST_REACH = 260.0;

// Value noise read from a small tileable texture of random values
// (BackdropLife.noise_texture, 128 x 128): one filtered read where the
// arithmetic version cost four hashes — the difference on a phone's GPU.
// textureLod, not texture: it is read inside loops and branches.
uniform sampler2D life_noise_tex : repeat_enable, filter_linear;
const float LIFE_NOISE_SIZE = 128.0;

float life_noise(vec2 p) {
	return textureLod(life_noise_tex, (p + 0.5) / LIFE_NOISE_SIZE, 0.0).r;
}

// True when nothing can happen at this pixel: no zone in its block, no
// lightning, nothing that looks like a flame. The shader then draws the
// painting as it is and skips the rest — most of a picture is quiet.
bool life_quiet(vec2 px, vec4 col) {
	if (life_flash > 0.0) {
		return false;
	}
	ivec2 cell = ivec2(floor(px / LIFE_CELL));
	ivec2 cells = textureSize(life_cells, 0);
	if (life_count > 0 && cell.x >= 0 && cell.y >= 0 && cell.x < cells.x && cell.y < cells.y
			&& texelFetch(life_cells, cell, 0).rgb != vec3(0.0)) {
		return false;
	}
	float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	return !(life_flame > 0.0 && col.r > col.b && lum > life_flame_floor - 0.2);
}

float life_edge(vec2 px, vec4 r) {
	float feather = clamp(min(r.z, r.w) * 0.25, 2.0, 24.0);
	vec2 a = smoothstep(r.xy, r.xy + feather, px) * (1.0 - smoothstep(r.xy + r.zw - feather, r.xy + r.zw, px));
	return a.x * a.y;
}

// A heartbeat: two beats close together, then rest.
float life_beat(float t) {
	float c = fract(t);
	return exp(-pow((c - 0.10) * 22.0, 2.0)) + 0.6 * exp(-pow((c - 0.28) * 22.0, 2.0));
}

// What the zones ask of one pixel. The texture is sampled by the shader's own
// fragment() (a built-in TEXTURE cannot be handed to a function), in three
// reads at most: the pixel moved by offset, by offset + ripple where there is
// water, by offset + melt where there is lava — then life_finish().
struct Life {
	vec2 offset;
	vec2 ripple;
	vec2 melt;
	float wet;
	float wet_floor;
	float molten;
	float falls;
	float glint;
	vec3 glow;
	float lava;
	float stars;
	float pulse;
	bool touched;  // some zone reached this pixel
};

Life life_gather(vec2 px, float t) {
	Life l;
	l.offset = vec2(0.0);
	l.ripple = vec2(0.0);
	l.melt = vec2(0.0);
	l.wet = 0.0;
	l.wet_floor = 0.0;
	l.molten = 0.0;
	l.falls = 0.0;
	l.glint = 0.0;
	l.glow = vec3(0.0);
	l.lava = 0.0;
	l.stars = 0.0;
	l.pulse = 0.0;
	l.touched = false;
	ivec2 cell = ivec2(floor(px / LIFE_CELL));
	ivec2 cells = textureSize(life_cells, 0);
	int mask = 0;
	if (life_count > 0 && cell.x >= 0 && cell.y >= 0 && cell.x < cells.x && cell.y < cells.y) {
		ivec3 bits = ivec3(round(texelFetch(life_cells, cell, 0).rgb * 255.0));
		mask = bits.r | (bits.g << 8) | (bits.b << 16);
	}
	for (int i = 0; i < LIFE_ZONES; i++) {
		if (mask == 0 || i >= life_count) {
			break;
		}
		if (((mask >> i) & 1) == 0) {
			continue;
		}
		mask &= ~(1 << i);
		vec4 r = life_rect[i];
		if (px.x < r.x || px.y < r.y || px.x > r.x + r.z || px.y > r.y + r.w) {
			continue;
		}
		float w = life_edge(px, r);
		l.touched = true;
		vec4 s = life_shape[i];
		int kind = int(s.x + 0.5);
		float k = s.y;
		float sp = s.z;
		vec2 local = (px - r.xy) / r.zw;
		if (kind == 0) {
			l.offset.x += (life_noise(vec2(px.x * 0.35, px.y * 0.06 - t * sp * 3.0)) - 0.5) * k * 1.2 * w;
			l.falls += w * k * smoothstep(0.55, 0.95, life_noise(vec2(px.x * 0.45, px.y * 0.035 - t * sp * 2.6)));
		} else if (kind == 1) {
			float stir = 1.0 + 2.0 * life_wind.z * clamp(1.0 - distance(px, life_wind.xy) / LIFE_GUST_REACH, 0.0, 1.0);
			l.ripple.x += sin(px.y * 0.85 + t * sp * 2.2 * stir + px.x * 0.015) * k * 1.1 * w * stir;
			l.wet = max(l.wet, w);
			l.wet_floor = s.w;
			float g = sin(px.x * 0.11 + t * sp * 1.9) * sin(px.y * 0.6 - t * sp * 1.3 + px.x * 0.03);
			l.glint += w * k * smoothstep(0.86, 1.0, g);
		} else if (kind == 2) {
			float along = s.w < 0.5 ? local.y : 1.0 - local.y;
			float phase = r.x * 0.013 + r.y * 0.007;
			float gust = 0.75 + 0.25 * sin(t * sp * 0.37 + phase * 3.0);
			l.offset.x -= sin(t * sp + phase + local.y * 1.4) * k * along * along * gust * w;
			// a gust: pushed its way, or set swinging by a blow from above or below
			float near = life_wind.z * clamp(1.0 - distance(r.xy + r.zw * 0.5, life_wind.xy) / LIFE_GUST_REACH, 0.0, 1.0);
			float push = life_wind.w + (1.0 - abs(life_wind.w)) * sin(t * 8.0 + phase * 5.0);
			l.offset.x -= push * near * k * 1.8 * along * along * w;
		} else if (kind == 3) {
			vec2 d = (local - 0.5) * 2.0;
			float fall = clamp(1.0 - dot(d, d), 0.0, 1.0);
			float breath = 0.55 + 0.3 * sin(t * sp) + 0.15 * life_noise(vec2(t * sp * 0.7, float(i)));
			l.glow += life_tint[i].rgb * (w * k * fall * (breath * (1.0 + life_rage * 1.5) + life_exhale * 1.5));
		} else if (kind == 4) {
			vec2 flow = vec2(life_noise(px * 0.045 + vec2(t * sp * 0.6, 0.0)), life_noise(px * 0.045 - vec2(0.0, t * sp * 0.9) + 7.0));
			l.melt += (flow - 0.5) * k * 1.6 * w;
			l.molten = max(l.molten, w);
			l.lava += w * k * (1.0 + life_rage) * (life_noise(px * 0.03 - vec2(t * sp * (0.25 + life_rage * 0.25), t * sp * 0.4)) - 0.35);
		} else if (kind == 5) {
			float rise = t * sp * 2.5;
			vec2 shimmer = vec2(life_noise(px * vec2(0.09, 0.05) + vec2(0.0, rise)), life_noise(px * vec2(0.05, 0.09) + vec2(3.0, rise)));
			l.offset += (shimmer - 0.5) * k * 1.8 * (1.0 + life_rage * 0.4) * w * (0.35 + 0.65 * local.y);
		} else if (kind == 6) {
			l.stars += w * k * (life_noise(floor(px / 2.0) * 0.9 + vec2(t * sp, 0.0)) - 0.5);
		} else if (kind == 7) {
			float clock = life_beat_clock < 0.0 ? t : life_beat_clock;
			l.pulse += w * k * (1.0 + life_dread + life_rage) * life_beat(clock * sp + local.x * 0.15);
		}
	}
	l.offset *= life_motion;
	l.ripple *= life_motion;
	l.melt *= life_motion;
	return l;
}

float life_lum(vec4 c) {
	return dot(c.rgb, vec3(0.299, 0.587, 0.114));
}

vec4 life_finish(vec4 col, vec4 wet_col, vec4 hot_col, Life l, vec2 px, float t) {
	float glint = l.glint;
	// Ripples move only what reflects: both this pixel and the one it borrows
	// must be lit water, so a post or a reed standing in it keeps still.
	if (l.wet > 0.0) {
		float here = smoothstep(l.wet_floor, l.wet_floor + 0.06, life_lum(col));
		col = mix(col, wet_col, here * smoothstep(l.wet_floor, l.wet_floor + 0.06, life_lum(wet_col)));
		glint *= here;
	}
	// Lava flows the same way: only where it and what it borrows are molten,
	// so the rock and masonry around it stay put.
	if (l.molten > 0.0) {
		float here = smoothstep(0.3, 0.45, life_lum(col)) * clamp((col.r - col.b) * 2.2, 0.0, 1.0);
		float there = smoothstep(0.3, 0.45, life_lum(hot_col)) * clamp((hot_col.r - hot_col.b) * 2.2, 0.0, 1.0);
		col = mix(col, hot_col, here * there);
	}
	float lum = life_lum(col);
	float warm = clamp((col.r - col.b) * 2.2, 0.0, 1.0);
	// most of a picture is quiet: no zone, no flame, no lightning — as painted
	bool flame_like = life_flame > 0.0 && warm > 0.0 && lum > life_flame_floor - 0.2;
	if (!l.touched && !flame_like && life_flash <= 0.0) {
		return col;
	}
	float cool = clamp((col.b - col.r) * 3.0, 0.0, 1.0);
	// Each flame flickers on its own: the noise cell is about a candle wide.
	// only what could be a flame or its glow pays for the noise
	if (flame_like) {
		float flame = smoothstep(life_flame_floor, life_flame_floor + 0.25, lum) * warm;
		float flick = life_noise(px / 5.0 + vec2(t * 5.3, t * 1.7)) * 0.7 + life_noise(px / 11.0 - vec2(t * 2.1, 0.0)) * 0.3 - 0.5;
		col.rgb *= 1.0 + life_light * flame * (life_flame * (1.0 + life_rage * 0.6) * flick * 1.4 + life_exhale * 0.25);
		// the flame and the warm glow around it take the colour of his path
		float halo = smoothstep(life_flame_floor - 0.2, life_flame_floor + 0.1, lum) * warm;
		col.rgb = mix(col.rgb, life_lum(col) * life_lean.rgb * 1.5, halo * life_lean.a * 0.85);
	}
	col.rgb += vec3(0.72, 0.84, 1.0) * l.falls * smoothstep(0.18, 0.55, lum) * cool * 0.4 * life_light;
	col.rgb += vec3(0.85, 0.9, 1.0) * glint * smoothstep(0.08, 0.4, lum) * 0.35 * life_light;
	col.rgb += l.glow * (0.25 + lum) * life_light;
	col.rgb *= 1.0 + l.lava * warm * smoothstep(0.25, 0.7, lum) * life_light;
	col.rgb *= 1.0 + l.stars * smoothstep(0.5, 0.85, lum) * (1.0 - warm) * 2.0 * life_light;
	float red = smoothstep(0.08, 0.3, col.r - max(col.g, col.b));
	col.rgb *= 1.0 + l.pulse * red * 0.3 * life_light;
	col.rgb += life_flash_tint * life_flash * life_light * (0.15 + cool) * smoothstep(0.1, 0.55, lum) * 0.5;
	return col;
}
