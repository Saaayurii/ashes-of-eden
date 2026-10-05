shader_type canvas_item;
// The painting itself, alive: assets/shaders/backdrop_life.gdshaderinc.
#include "res://assets/shaders/backdrop_life.gdshaderinc"

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	Life l = life_gather(px, TIME);
	vec4 col = texture(TEXTURE, UV + l.offset * TEXTURE_PIXEL_SIZE);
	vec4 wet = l.wet > 0.0 ? texture(TEXTURE, UV + (l.offset + l.ripple) * TEXTURE_PIXEL_SIZE) : col;
	vec4 hot = l.molten > 0.0 ? texture(TEXTURE, UV + (l.offset + l.melt) * TEXTURE_PIXEL_SIZE) : col;
	COLOR = life_finish(col, wet, hot, l, px, TIME) * tint;
}
