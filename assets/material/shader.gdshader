shader_type spatial;
render_mode ambient_light_disabled, specular_disabled, cull_disabled;

global uniform vec3 tap_origin;
global uniform float tap_radius;

uniform sampler2D ink_texture : source_color, hint_default_white, filter_nearest;
uniform float outline_thickness : hint_range(0.0, 1.0) = 0.42;
uniform bool use_floor_grid = true;
uniform float grid_size = 1.5;
uniform float hatch_threshold : hint_range(0.0, 0.5) = 0.12;
uniform float hatch_scale : hint_range(0.1, 3.0) = 0.75;

group_uniforms Comic_Wear;
uniform bool enable_comic_wear = true;
uniform float wear_scale : hint_range(0.5, 10.0) = 1.2;
uniform float wear_density : hint_range(0.0, 1.0) = 0.15;
uniform float wear_thickness : hint_range(0.005, 0.04) = 0.015;

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

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

vec2 get_triplanar_uv(vec3 pos, vec3 norm) {
	vec3 anorm = abs(norm);
	if (anorm.y > anorm.x && anorm.y > anorm.z) {
		return pos.xz;
	} else if (anorm.x > anorm.z) {
		return pos.yz;
	}
	return pos.xy;
}

float get_comic_scratches(vec2 p, float scale, float density, float thickness) {
	vec2 cell_coord = p * scale;
	vec2 cell_id = floor(cell_coord);
	vec2 cell_uv = fract(cell_coord) - 0.5;
	vec2 rnd = hash22(cell_id);

	if (rnd.x > density) {
		return 0.0;
	}

	float angle = (rnd.y - 0.5) * 2.6;
	vec2 dir = vec2(cos(angle), sin(angle));
	vec2 norm_dir = vec2(-dir.y, dir.x);

	vec2 offset = (hash22(cell_id + vec2(13.7, 41.3)) - 0.5) * 0.35;
	vec2 uv_o = cell_uv - offset;

	float d_along = dot(uv_o, dir);
	float d_perp = abs(dot(uv_o, norm_dir));
	float len = 0.25 + rnd.x * 0.45;

	// Goresan utama pena komik
	float line1 = step(abs(d_along), len) * step(d_perp, thickness);

	// Goresan sekunder pendek (// gaya goresan komik)
	float line2 = 0.0;
	if (rnd.y > 0.42) {
		float gap = 0.032 + rnd.x * 0.018;
		float len2 = len * (0.45 + rnd.y * 0.4);
		float d2_along = d_along + (rnd.x - 0.5) * 0.08;
		float d2_perp = abs(d_perp - gap);
		line2 = step(abs(d2_along), len2) * step(d2_perp, thickness * 0.85);
	}

	// Coretan silang kecil (X) sesekali muncul
	float cross_line = 0.0;
	if (rnd.x < 0.08 * density) {
		float c_angle = angle + 1.25;
		vec2 c_dir = vec2(cos(c_angle), sin(c_angle));
		vec2 c_norm = vec2(-c_dir.y, c_dir.x);
		float c_along = dot(uv_o, c_dir);
		float c_perp = abs(dot(uv_o, c_norm));
		cross_line = step(abs(c_along), len * 0.55) * step(c_perp, thickness);
	}

	return clamp(line1 + line2 + cross_line, 0.0, 1.0);
}

float get_comic_lines(vec3 normal, vec3 view) {
	// Hitung turunan screen-space di fragment() agar valid di gl_compatibility
	vec3 normal_jump = fwidth(normal);
	float normal_delta = length(normal_jump);
	vec2 grid_deriv = max(fwidth(world_pos.xz / grid_size), vec2(0.0001));

	// Deteksi apakah ini lantai datar atau plafon ruangan
	float is_ground_or_ceiling = step(2.6, world_pos.y) + (1.0 - step(0.25, world_pos.y));
	float is_flat_floor = step(0.95, abs(world_normal.y)) * is_ground_or_ceiling;

	// 1. Garis Siluet Pinggiran (Khusus permukaan lengkung agar bidang datar kubus tidak menghitam)
	float is_curved = step(0.003, normal_delta);
	float rim_edge = (1.0 - max(dot(normal, view), 0.0)) * (1.0 - is_flat_floor) * is_curved;
	float rim_outline = step(1.0 - outline_thickness, rim_edge);

	// 2. Garis Siku Tajam (Hanya muncul di sudut patahan objek)
	float hard_corner = step(0.12, normal_delta);

	// 3. Garis Ubin Khusus Lantai & Plafon (Bukan Meja/Prop)
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
	} else if (enable_comic_wear) {
		vec2 tri_uv = get_triplanar_uv(world_pos, world_normal);
		float scratch = get_comic_scratches(tri_uv, wear_scale, wear_density, wear_thickness);
		if (scratch > 0.5) {
			ink = 0.0;
		}
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
	// Untuk bidang dua-sisi (seperti plafon/atap), balik normal jika cahaya datang dari arah belakang
	vec3 n = NORMAL;
	if (dot(n, LIGHT) < 0.0) {
		n = -n;
	}
	float NdotL = max(dot(n, LIGHT), 0.0);
	float light_intensity = max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b));
	float in_light = step(0.05, ATTENUATION) * step(0.01, NdotL) * step(0.01, light_intensity);

	float lit_val = in_light;
	// Arsir tinta tipis hanya pada bidang vertikal/lengkung yang menyerempet cahaya (bukan permukaan horizontal seperti meja/lantai)
	if (hatch_threshold > 0.001 && in_light > 0.5 && NdotL < hatch_threshold && abs(world_normal.y) < 0.85) {
		lit_val *= 1.0 - step(0.85, sin((FRAGCOORD.x + FRAGCOORD.y) * hatch_scale));
	}

	// Di luar senter = 100% Hitam, di dalam senter = 100% Putih bersih dengan Garis Tepi/Ubin Hitam!
	DIFFUSE_LIGHT += ALBEDO * lit_val;
}
