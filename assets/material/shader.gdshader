shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

// Tekstur garis hitam-putih dari Blender (Opsional: kalau kosong, otomatis putih polos)
uniform sampler2D ink_texture : source_color, hint_default_white, filter_nearest;

uniform float outline_thickness : hint_range(0.0, 1.0) = 0.45;
uniform bool use_floor_grid = true;
uniform float grid_size = 2.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Membaca gambar hitam-putih dari Blender (jika ada)
	vec4 tex = texture(ink_texture, UV);
	// Memastikan warnanya tegas 1-Bit (Hitam atau Putih saja, tanpa blur!)
	ALBEDO = vec3(step(0.5, (tex.r + tex.g + tex.b) / 3.0));
}

void light() {
	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float in_light = step(0.05, ATTENUATION) * step(0.01, NdotL);
	
	if (in_light < 0.5) {
		DIFFUSE_LIGHT += vec3(0.0);
	} else {
		float rim_edge = 1.0 - max(dot(NORMAL, VIEW), 0.0);
		vec3 normal_jump = fwidth(NORMAL);
		float hard_corner = step(0.15, length(normal_jump));
		
		float is_floor_or_ceiling = step(0.8, abs(world_normal.y));
		float rim_outline = step(1.0 - outline_thickness, rim_edge) * (1.0 - is_floor_or_ceiling);
		float is_outline = max(rim_outline, hard_corner);
		
		float floor_line = 0.0;
		if (use_floor_grid && is_floor_or_ceiling > 0.5) {
			vec2 grid = abs(fract(world_pos.xz / grid_size - 0.5) - 0.5) / fwidth(world_pos.xz / grid_size);
			float line = min(grid.x, grid.y);
			floor_line = 1.0 - min(line, 1.0);
		}
		
		// Menggabungkan warna putih permukaan dengan garis tekstur dari Blender (ALBEDO)
		float final_ink = ALBEDO.r;
		if (is_outline > 0.5 || floor_line > 0.35) {
			final_ink = 0.0;
		}
		
		DIFFUSE_LIGHT += vec3(final_ink);
	}
}