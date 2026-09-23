shader_type canvas_item;
// Thin moving highlights over a painted water area: reads as shimmer, costs nothing.
uniform float speed = 0.5;
uniform float strength : hint_range(0.0, 1.0) = 0.22;
uniform float scale = 55.0;

void fragment() {
	float w1 = sin(UV.x * scale + TIME * speed * 3.1) * sin(UV.y * scale * 0.45 - TIME * speed * 1.7);
	float w2 = sin(UV.x * scale * 1.7 - TIME * speed * 2.3 + UV.y * 9.0);
	float line = smoothstep(0.82, 1.0, w1) + 0.5 * smoothstep(0.9, 1.0, w2);
	float fade = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));
	COLOR = vec4(0.8, 0.86, 1.0, line * strength * fade);
}
