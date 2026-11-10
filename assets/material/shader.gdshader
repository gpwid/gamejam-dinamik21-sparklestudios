shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

global uniform vec3 tap_origin;
global uniform float tap_radius;

uniform sampler2D ink_texture : source_color, hint_default_white, filter_nearest;
uniform float outline_thickness : hint_range(0.0, 1.0) = 0.42;
uniform bool use_floor_grid = true;
uniform float grid_size = 1.5;

// --- PENGATURAN BANYAK GELOMBANG (MULTI-RIPPLE) ---
const float MAX_TAP_DISTANCE = 9.0;
const float WAVE_SPREAD = 3.2;     // Lebar rombongan gelombang
const float WAVE_FREQUENCY = 15.0; // Banyaknya cincin gelombang

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float get_comic_lines(vec3 normal, vec3 view) {
	// Deteksi apakah ini lantai datar di bawah
	float is_flat_floor = step(0.95, abs(world_normal.y)) * step(world_pos.y, 0.35);
	
	// 1. Garis Siluet Pinggiran (Membuat Tabung, Donat, dan Objek punya outline hitam bersih)
	float rim_edge = (1.0 - max(dot(normal, view), 0.0)) * (1.0 - is_flat_floor);
	float rim_outline = step(1.0 - outline_thickness, rim_edge);
	
	// 2. Garis Siku Tajam (Hanya muncul di sudut patahan objek)
	vec3 normal_jump = fwidth(normal);
	float hard_corner = step(0.12, length(normal_jump));
	
	// 3. Garis Ubin Khusus Lantai
	float floor_line = 0.0;
	if (use_floor_grid && is_flat_floor > 0.5) {
		vec2 grid = abs(fract(world_pos.xz / grid_size - 0.5) - 0.5) / fwidth(world_pos.xz / grid_size);
		float line = min(grid.x, grid.y);
		floor_line = 1.0 - min(line, 1.0);
	}
	
	return max(max(rim_outline, hard_corner), step(0.4, floor_line));
}

void fragment() {
	vec4 tex = texture(ink_texture, UV);
	ALBEDO = vec3(step(0.5, (tex.r + tex.g + tex.b) / 3.0));
	
	// --- EFEK BANYAK GELOMBANG BERUNTUN (MULTI-RIPPLE) ---
	EMISSION = vec3(0.0);
	if (tap_radius > 0.01 && tap_radius < MAX_TAP_DISTANCE) {
		float dist = distance(world_pos, tap_origin);
		float dist_behind_front = tap_radius - dist;
		
		if (dist_behind_front >= 0.0 && dist_behind_front <= WAVE_SPREAD) {
			// Menghasilkan banyak cincin gelombang putih yang bersih
			float multi_rings = step(0.5, sin(dist_behind_front * WAVE_FREQUENCY));
			float trail_fade = 1.0 - (dist_behind_front / WAVE_SPREAD);
			float distance_fade = 1.0 - smoothstep(MAX_TAP_DISTANCE * 0.65, MAX_TAP_DISTANCE, tap_radius);
			
			EMISSION = vec3(multi_rings * trail_fade * distance_fade);
		}
	}
}

void light() {
	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float in_light = step(0.05, ATTENUATION) * step(0.01, NdotL);
	
	// Di luar senter = 100% Hitam
	if (in_light < 0.5) {
		DIFFUSE_LIGHT += vec3(0.0);
	} else {
		// Di dalam senter = 100% Putih bersih dengan Garis Tepi/Ubin Hitam!
		float comic_edge = get_comic_lines(NORMAL, VIEW);
		float final_ink = ALBEDO.r;
		
		if (comic_edge > 0.5) {
			final_ink = 0.0;
		}
		
		DIFFUSE_LIGHT += vec3(final_ink);
	}
}