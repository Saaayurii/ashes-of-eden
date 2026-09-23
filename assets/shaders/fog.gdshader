shader_type canvas_item;
// Two layers of scrolling seamless noise, denser towards the bottom.
uniform sampler2D noise : repeat_enable, filter_linear;
uniform float speed = 0.015;
uniform float density : hint_range(0.0, 1.0) = 0.45;
uniform vec4 tint : source_color = vec4(0.72, 0.74, 0.82, 1.0);
uniform float bottom_bias : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec2 uv = UV;
	float a = texture(noise, uv * vec2(1.0, 2.2) + vec2(TIME * speed, 0.0)).r;
	float b = texture(noise, uv * vec2(1.9, 1.3) - vec2(TIME * speed * 0.55, TIME * 0.004)).r;
	float f = smoothstep(0.38, 0.85, (a + b) * 0.5);
	float vertical = mix(1.0, smoothstep(0.15, 1.0, uv.y), bottom_bias);
	COLOR = vec4(tint.rgb, f * density * vertical);
}
