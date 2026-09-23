shader_type canvas_item;
// A tint that lives on the edges of the screen and leaves the middle alone:
// the red that comes up around the frame when the hero is hit
// (scripts/ui/screen_fx.gd). Runs on GL Compatibility and the Web build.

uniform vec4 tint : source_color = vec4(0.75, 0.04, 0.03, 1.0);
// 0 = nothing, 1 = the whole frame burning.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// How far in from the edge the tint starts (0 = centre, 1 = edge midpoints).
uniform float inner : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec2 d = abs(UV - vec2(0.5)) * 2.0;
	// Between a circle and a square, so all four sides glow, not just the corners.
	float edge = mix(length(d), max(d.x, d.y), 0.6);
	float v = smoothstep(inner, 1.25, edge);
	COLOR = vec4(tint.rgb, tint.a * v * strength);
}
