shader_type canvas_item;
// The painting itself, alive: assets/shaders/backdrop_life.gdshaderinc.
#include "res://assets/shaders/backdrop_life.gdshaderinc"

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	vec4 still = texture(TEXTURE, UV);
	if (life_quiet(px, still)) {
		COLOR = still * tint;
	} else {
		Life l = life_gather(px, TIME);
		vec4 col = texture(TEXTURE, UV + l.offset * TEXTURE_PIXEL_SIZE);
		// branches, not ?:, and textureLod: an implicit-LOD read in a branch
		// makes the GPU take it on every pixel (backdrop_life_bench.gd)
		vec4 wet = col;
		if (l.wet > 0.0) {
			wet = textureLod(TEXTURE, UV + (l.offset + l.ripple) * TEXTURE_PIXEL_SIZE, 0.0);
		}
		vec4 hot = col;
		if (l.molten > 0.0) {
			hot = textureLod(TEXTURE, UV + (l.offset + l.melt) * TEXTURE_PIXEL_SIZE, 0.0);
		}
		COLOR = life_finish(col, wet, hot, l, px, TIME) * tint;
	}
}
