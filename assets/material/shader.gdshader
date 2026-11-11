shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

global uniform vec3 tap_origin;
global uniform float tap_radius;

uniform sampler2D ink_texture : source_color, hint_default_white, filter_nearest;
uniform float outline_thickness : hint_range(0.0, 1.0) = 0.42;
uniform bool use_floor_grid = true;
uniform float grid_size = 1.5;

// --- PENGATURAN GELOMBANG GANDA (DOUBLE-RIPPLE DENGAN AFTERGLOW TRAIL) ---
const float MAX_TAP_DISTANCE = 18.0;
const float WAVE_GAP = 2.6;          // Jarak jeda antara cincin primer dan sekunder (meter)
const float TRAIL_LENGTH = 3.2;      // Panjang ekor pendaran afterglow agar terbaca jelas oleh pemain

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

// Fungsi kurva gelombang: kepala tajam dengan ekor pendaran (phosphorescent afterglow)
float get_wave_intensity(float dist, float front_radius, float trail_len) {
	if (front_radius <= 0.05) {
		return 0.0;
	}
	float delta = front_radius - dist;
	// Di depan kepala gelombang (soft leading edge 0.3m)
	if (delta < 0.0) {
		return smoothstep(-0.3, 0.0, delta);
	}
	// Di belakang kepala gelombang (pendaran memudar di sepanjang trail_len)
	if (delta <= trail_len) {
		return pow(1.0 - (delta / trail_len), 1.3);
	}
	return 0.0;
}

void fragment() {
	vec4 tex = texture(ink_texture, UV);
	ALBEDO = vec3(step(0.5, (tex.r + tex.g + tex.b) / 3.0));
	
	// --- EFEK GELOMBANG GANDA (DOUBLE-RIPPLE ECHOLOCATION DENGAN AFTERGLOW) ---
	EMISSION = vec3(0.0);
	if (tap_radius > 0.05 && tap_radius < MAX_TAP_DISTANCE) {
		float dist = distance(world_pos, tap_origin);
		
		// 1. Cincin Primer (depan) pada radius tap_radius dengan ekor afterglow
		float ring1 = get_wave_intensity(dist, tap_radius, TRAIL_LENGTH);
		
		// 2. Cincin Sekunder (belakang) mengekor di (tap_radius - WAVE_GAP)
		// Hanya muncul jika tap_radius > WAVE_GAP untuk mencegah anomali di titik awal
		float ring2 = 0.0;
		if (tap_radius > WAVE_GAP) {
			float r2 = tap_radius - WAVE_GAP;
			ring2 = get_wave_intensity(dist, r2, TRAIL_LENGTH) * 0.85;
		}
		
		// 3. Gabungkan intensitas kedua cincin (clamp 0.0 - 1.0)
		float combined_wave = clamp(ring1 + ring2, 0.0, 1.0);
		
		// Fade out halus saat mendekati batas maksimal jangkauan
		float distance_fade = 1.0 - smoothstep(MAX_TAP_DISTANCE * 0.75, MAX_TAP_DISTANCE, tap_radius);
		float wave_intensity = combined_wave * distance_fade;
		
		if (wave_intensity > 0.005) {
			// Pertahankan gaya comic ink: garis siluet, sudut tajam, dan grid ubin tetap hitam
			float comic_edge = get_comic_lines(NORMAL, VIEW);
			float wave_ink = (comic_edge > 0.5) ? 0.0 : 1.0;
			EMISSION = vec3(wave_ink * wave_intensity);
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
