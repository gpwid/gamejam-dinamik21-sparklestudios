shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float max_blur_lod : hint_range(0.0, 5.0) = 3.5;
uniform float static_intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 col = vec4(0.0);
	if (blur_intensity > 0.001) {
		float effective_lod = blur_intensity * max_blur_lod;
		vec2 ps = SCREEN_PIXEL_SIZE * (blur_intensity * 3.5);

		// Multi-tap spatial + mipmap sampling for smooth, cinematic vision blur
		vec4 sum = vec4(0.0);
		sum += textureLod(screen_texture, SCREEN_UV, effective_lod) * 0.22;
		sum += textureLod(screen_texture, SCREEN_UV + vec2(ps.x, 0.0), effective_lod) * 0.12;
		sum += textureLod(screen_texture, SCREEN_UV - vec2(ps.x, 0.0), effective_lod) * 0.12;
		sum += textureLod(screen_texture, SCREEN_UV + vec2(0.0, ps.y), effective_lod) * 0.12;
		sum += textureLod(screen_texture, SCREEN_UV - vec2(0.0, ps.y), effective_lod) * 0.12;
		sum += textureLod(screen_texture, SCREEN_UV + vec2(ps.x, ps.y) * 0.7071, effective_lod) * 0.075;
		sum += textureLod(screen_texture, SCREEN_UV + vec2(-ps.x, ps.y) * 0.7071, effective_lod) * 0.075;
		sum += textureLod(screen_texture, SCREEN_UV + vec2(ps.x, -ps.y) * 0.7071, effective_lod) * 0.075;
		sum += textureLod(screen_texture, SCREEN_UV + vec2(-ps.x, -ps.y) * 0.7071, effective_lod) * 0.075;

		col = vec4(sum.rgb, blur_intensity);
	}

	if (static_intensity > 0.001) {
		vec2 uv = SCREEN_UV;
		vec2 center = uv - 0.5;
		float dist = length(center);
		// Vignette mask: concentrates around screen perimeter
		float vig = smoothstep(0.32, 0.78, dist);

		// 1-Bit pseudo-random noise stepped to crisp white dots/lines
		float n = fract(sin(dot(floor(uv * vec2(320.0, 240.0)) + floor(TIME * 24.0), vec2(12.9898, 78.233))) * 43758.5453);
		float bit = step(0.70, n);
		float alpha = bit * vig * static_intensity;

		col = mix(col, vec4(1.0, 1.0, 1.0, 1.0), alpha);
	}

	COLOR = col;
}
