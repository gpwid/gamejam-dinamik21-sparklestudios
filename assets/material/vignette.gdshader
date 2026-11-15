shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float max_blur_lod : hint_range(0.0, 5.0) = 3.5;

void fragment() {
	if (blur_intensity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
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

		COLOR = vec4(sum.rgb, blur_intensity);
	}
}
