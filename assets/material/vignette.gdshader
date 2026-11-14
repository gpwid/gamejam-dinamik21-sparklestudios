shader_type canvas_item;

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.85, 0.05, 0.05, 1.0);
uniform float pulse_speed : hint_range(0.0, 10.0) = 4.3;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv * vec2(1.25, 1.0));
	float vig = smoothstep(0.25, 0.75, dist);
	float pulse = 0.8 + 0.2 * sin(TIME * pulse_speed);
	COLOR = vec4(vignette_color.rgb, vig * vignette_intensity * pulse * vignette_color.a);
}
