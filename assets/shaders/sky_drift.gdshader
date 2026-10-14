shader_type canvas_item;
// The main menu's sky (scripts/ui/menu_sky.gd): clouds drift over the painted
// ones. Drawn over the painting — after its own life — and reads it back, so
// nothing is painted on: thick cloud dims the sky as it passes, a gap lets the
// light through, thin scud slides along the lit sky and behind every
// silhouette (dark pixels stay as painted), and a lightning stroke lights the
// clouds from inside. Quantised to painting pixels, so it stays pixel art.

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform sampler2D noise : repeat_enable, filter_linear;
// painting pixels the rect covers
uniform vec2 size = vec2(640.0, 160.0);
// seconds, advanced by the script only while the backdrop may move
uniform float clock = 0.0;
// how far a passing cloud dims or lights the sky
uniform float shade = 0.26;
// how much thin scud there is
uniform float scud = 0.35;
// Settings.flash_scale(): how far light may change
uniform float light = 1.0;
// a lightning stroke, 0..1
uniform float flash = 0.0;
uniform vec3 flash_tint = vec3(0.7, 0.78, 1.0);

void fragment() {
	vec2 px = floor(UV * size) + 0.5;
	vec3 base = texture(screen, SCREEN_UV).rgb;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec2 p = px / vec2(640.0, 360.0);
	// two decks: the high one slow, the low one quicker, both with the wind (to the left)
	float high = texture(noise, p * vec2(1.3, 3.2) + vec2(clock * 0.0045, 0.0)).r;
	float low = texture(noise, p * vec2(2.6, 6.5) + vec2(clock * 0.012, clock * 0.0006) + high * 0.2).r;
	float thick = smoothstep(0.4, 0.75, high * 0.55 + low * 0.45);
	float wisp = smoothstep(0.55, 0.8, texture(noise, p * vec2(3.0, 6.5) + vec2(clock * 0.02, 0.0) + low * 0.12).r);
	// sky only: fades out towards the horizon, silhouettes stay as painted
	float sky = smoothstep(1.0, 0.6, UV.y) * smoothstep(0.1, 0.24, lum);
	float warm = clamp((base.r - base.b) * 3.0, 0.0, 1.0);
	float lit = smoothstep(0.25, 0.6, lum);
	vec3 col = base * (1.0 + sky * shade * light * mix(0.8, -1.0, thick) * (0.4 + lit));
	// scud takes the colour of the light it crosses: warm near the gap, grey away from it
	vec3 scud_col = mix(vec3(0.5, 0.5, 0.53), vec3(0.95, 0.78, 0.58), warm * lit);
	col = mix(col, scud_col, wisp * scud * sky * (0.4 + lit * 0.6));
	col += flash_tint * flash * light * sky * (0.3 + thick) * 0.6;
	COLOR = vec4(col, 1.0);
}
