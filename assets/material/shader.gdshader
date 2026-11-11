shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

global uniform vec3 tap_origin;
global uniform float tap_radius;

uniform sampler2D ink_texture : source_color, hint_default_white, filter_nearest;
uniform float outline_thickness : hint_range(0.0, 1.0) = 0.42;
uniform bool use_floor_grid = true;
uniform float grid_size = 1.5;
uniform float hatch_threshold : hint_range(0.0, 0.5) = 0.12;
uniform float hatch_scale : hint_range(0.1, 3.0) = 0.75;

// --- PENGATURAN GELOMBANG GANDA (DOUBLE-RIPPLE DENGAN AFTERGLOW TRAIL) ---
const float MAX_TAP_DISTANCE = 18.0;
const float WAVE_GAP = 3.5;          // Jarak jeda antara cincin primer dan sekunder (3.5m)
const float WAVE_THICKNESS = 3.5;    // Ketebalan pendaran gelombang (smooth trail) agar garis ruangan terbaca jelas

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float get_comic_lines(vec3 normal, vec3 view) {
	// Hitung turunan screen-space di fragment() agar valid di gl_compatibility
	vec3 normal_jump = fwidth(normal);
	float normal_delta = length(normal_jump);
	vec2 grid_deriv = max(fwidth(world_pos.xz / grid_size), vec2(0.0001));

	// Deteksi apakah ini lantai datar di bawah
	float is_flat_floor = step(0.95, abs(world_normal.y)) * step(world_pos.y, 0.35);

	// 1. Garis Siluet Pinggiran (Khusus permukaan lengkung agar bidang datar kubus tidak menghitam)
	float is_curved = step(0.003, normal_delta);
	float rim_edge = (1.0 - max(dot(normal, view), 0.0)) * (1.0 - is_flat_floor) * is_curved;
	float rim_outline = step(1.0 - outline_thickness, rim_edge);

	// 2. Garis Siku Tajam (Hanya muncul di sudut patahan objek)
	float hard_corner = step(0.12, normal_delta);

	// 3. Garis Ubin Khusus Lantai
	float floor_line = 0.0;
	if (use_floor_grid && is_flat_floor > 0.5) {
		vec2 grid = abs(fract(world_pos.xz / grid_size - 0.5) - 0.5) / grid_deriv;
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
	// Di depan kepala gelombang (soft leading edge 0.35m)
	if (delta < 0.0) {
		return smoothstep(-0.35, 0.0, delta);
	}
	// Di belakang kepala gelombang (pendaran memudar di sepanjang trail_len)
	if (delta <= trail_len) {
		return pow(1.0 - (delta / trail_len), 1.2);
	}
	return 0.0;
}

void fragment() {
	vec4 tex = texture(ink_texture, UV);
	float comic_edge = get_comic_lines(NORMAL, VIEW);
	float ink = step(0.5, (tex.r + tex.g + tex.b) / 3.0);
	if (comic_edge > 0.5) {
		ink = 0.0;
	}
	ALBEDO = vec3(ink);

	// --- ECHOLOCATION: OUTLINE-ONLY (GARIS PUTIH DI ATAS LATAR HITAM) ---
	EMISSION = vec3(0.0);
	if (abs(tap_radius) > 0.05) {
		float dist = distance(world_pos, tap_origin);
		bool is_expanding = (tap_radius > 0.0);
		float current_r = is_expanding ? tap_radius : floor(abs(tap_radius));
		float global_fade = is_expanding ? 1.0 : fract(abs(tap_radius));

		if (dist <= current_r + 0.25) {
			// Area yang sudah tersapu gelombang
			float revealed_area = 1.0 - smoothstep(current_r - 0.4, current_r + 0.2, dist);

			// Garis tipis kepala gelombang primer & sekunder saat merambat
			float ring_front = 0.0;
			if (is_expanding) {
				float ring1_line = smoothstep(0.25, 0.0, abs(dist - current_r));
				float ring2_line = (current_r > WAVE_GAP) ? smoothstep(0.2, 0.0, abs(dist - (current_r - WAVE_GAP))) * 0.8 : 0.0;
				ring_front = clamp(ring1_line + ring2_line, 0.0, 1.0);
			}

			// HANYA nyalakan garis outline (comic_edge) dan garis cincin perambat
			float outline_only = step(0.5, comic_edge);
			float final_sonar = clamp(outline_only * revealed_area + ring_front, 0.0, 1.0) * global_fade;

			EMISSION = vec3(final_sonar);
		}
	}
}

void light() {
	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float in_light = step(0.05, ATTENUATION) * step(0.01, NdotL);

	float lit_val = in_light;
	// Arsir tinta tipis hanya pada bidang vertikal/lengkung yang menyerempet cahaya (bukan permukaan horizontal seperti meja/lantai)
	if (hatch_threshold > 0.001 && in_light > 0.5 && NdotL < hatch_threshold && abs(world_normal.y) < 0.85) {
		lit_val *= 1.0 - step(0.85, sin((FRAGCOORD.x + FRAGCOORD.y) * hatch_scale));
	}

	// Di luar senter = 100% Hitam, di dalam senter = 100% Putih bersih dengan Garis Tepi/Ubin Hitam!
	DIFFUSE_LIGHT += ALBEDO * lit_val;
}
