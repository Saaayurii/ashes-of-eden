shader_type canvas_item;
render_mode blend_add;
// Shafts of light fanning down from a point in the sky (the main menu's cross,
// scripts/ui/menu_sky.gd): bands that slowly turn and breathe as clouds pass
// in front of the light. Additive, quantised to painting pixels.

uniform sampler2D noise : repeat_enable, filter_linear;
// painting pixels the rect covers, and where the light is, in them
uniform vec2 size = vec2(640.0, 220.0);
uniform vec2 source = vec2(470.0, 47.0);
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float strength = 0.13;
// how far the shafts reach, painting pixels
uniform float reach = 170.0;
// seconds, advanced by the script only while the backdrop may move
uniform float clock = 0.0;
// Settings.flash_scale(): how far the light may breathe
uniform float light = 1.0;

void fragment() {
	vec2 px = floor(UV * size) + 0.5;
	vec2 d = px - source;
	float r = length(d);
	float angle = atan(d.x, d.y);
	// two sets of bands turning against each other, so shafts open and close
	float a = texture(noise, vec2(angle * 0.9 + clock * 0.012, 0.21 + clock * 0.004)).r;
	float b = texture(noise, vec2(angle * 2.3 - clock * 0.02, 0.63)).r;
	float shafts = smoothstep(0.4, 0.9, a * 0.6 + b * 0.4);
	// mostly downward, none straight up; nothing right on the source, fading with distance
	float down = smoothstep(-0.1, 0.5, d.y / max(r, 1.0));
	float fall = smoothstep(6.0, 26.0, r) * exp(-r / reach);
	float breath = 1.0 + light * 0.35 * sin(clock * 0.5) * sin(clock * 0.23 + 1.3);
	float vertical = smoothstep(1.0, 0.55, UV.y);
	COLOR = vec4(tint.rgb * shafts * down * fall * strength * breath * vertical, 1.0);
}
