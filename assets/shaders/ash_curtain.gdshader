shader_type canvas_item;
// The curtain between two rooms: the picture does not fade, it burns out.
// A noise front sweeps across the screen; where it passes the pixel turns to
// ash, and the front itself glows like an ember before it goes dark.
//
// progress 0 = the screen is clear, 1 = fully covered. The same shader runs
// backwards to uncover the room that was built behind it.
uniform sampler2D noise : repeat_enable, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ash : source_color = vec4(0.02, 0.018, 0.024, 1.0);
uniform vec4 ember : source_color = vec4(1.0, 0.55, 0.22, 1.0);
// How wide the burning front is, in units of progress.
uniform float edge : hint_range(0.02, 0.6) = 0.22;
// 0 = the front follows the noise alone, 1 = a straight sweep upwards.
uniform float sweep : hint_range(0.0, 1.0) = 0.4;
uniform float drift = 0.03;

void fragment() {
	float n = texture(noise, UV * vec2(1.7, 1.1) + vec2(TIME * drift, 0.0)).r;
	// Ash rises: the bottom of the screen goes first.
	float front = mix(n, 1.0 - UV.y, sweep);
	float p = mix(-edge, 1.0 + edge, progress);
	float cover = smoothstep(front - edge * 0.5, front + edge * 0.5, p);
	// Brightest halfway through, so the front reads as a line of embers.
	float glow = cover * (1.0 - cover) * 4.0;
	COLOR = vec4(mix(ash.rgb, ember.rgb, glow * ember.a), cover);
}
