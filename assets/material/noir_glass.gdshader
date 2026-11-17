shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// --- GLOBAL UNIFORMS (ECHOLOCATION DARI PLAYER) ---
global uniform vec3 tap_origin;
global uniform float tap_radius;

// --- PARAMETER KACA 1-BIT NOIR MANGA (MURNI HITAM-PUTIH TANPA WARNA) ---
group_uniforms Glass_Appearance;
uniform float rim_power : hint_range(0.5, 8.0) = 2.0;                  // Ketajaman siluet pinggiran
uniform float base_alpha : hint_range(0.0, 0.5) = 0.18;                // Transparansi badan kaca agar bervolume & tidak tembus plong
uniform float highlight_strength : hint_range(0.0, 2.0) = 1.0;         // Kilau pantulan diagonal komik
uniform float outline_thickness : hint_range(0.05, 0.5) = 0.22;        // Ketebalan garis kontur luar hitam

group_uniforms Glass_Wear;
uniform bool enable_glass_wear = true;
uniform float wear_density : hint_range(0.0, 1.0) = 0.25;

group_uniforms Echolocation;
uniform float echo_intensity : hint_range(0.5, 3.0) = 1.5;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 hash22_glass(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void fragment() {
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 1.0 - ndotv;

	// 1. Garis Kontur Siluet Komik (Pinggir Paling Luar = Tinta Hitam Pekat)
	// Agar tabung kaca terlihat jelas dan tegas saat berhadapan dengan dinding putih yang disorot senter
	float is_outer_rim = 1.0 - smoothstep(outline_thickness * 0.7, outline_thickness, ndotv);

	// 2. Garis Kilau Spesular Tinta Putih (Tepat di sebelah dalam garis kontur hitam)
	float inner_rim_start = outline_thickness;
	float inner_rim_end = outline_thickness + 0.24;
	float is_inner_rim = smoothstep(inner_rim_start * 0.9, inner_rim_start * 1.1, ndotv) * (1.0 - smoothstep(inner_rim_end * 0.8, inner_rim_end, ndotv));

	// 3. Kilau Pantulan Diagonal Khas Manga (Diagonal Manga Sheen Glints)
	float sheen_coord = (world_pos.y * 1.2) + (world_pos.x * 0.6) - (VIEW.x * 0.35);
	float sheen_sin1 = sin(sheen_coord * 1.5);
	float sheen_sin2 = sin((sheen_coord + 0.45) * 1.5);
	float sheen1 = smoothstep(0.40, 0.50, sheen_sin1) * smoothstep(0.60, 0.50, sheen_sin1);
	float sheen2 = smoothstep(0.44, 0.50, sheen_sin2) * smoothstep(0.56, 0.50, sheen_sin2) * 0.8;
	float comic_sheen = clamp(sheen1 + sheen2, 0.0, 1.0) * highlight_strength;

	// 4. Highlight Silinder Vertikal (Pendaran vertikal khas tabung kaca saat disorot)
	float vert_sheen = pow(clamp(dot(normalize(NORMAL.xz), normalize(VIEW.xz)), 0.0, 1.0), 12.0) * 0.4;

	// 5. Goresan Halus Kaca Laboratorium Usang
	float glass_scratch = 0.0;
	if (enable_glass_wear && wear_density > 0.01) {
		vec2 g_uv = vec2(world_pos.x * 0.7 + world_pos.z * 0.7, world_pos.y) * 4.5;
		vec2 g_id = floor(g_uv);
		vec2 g_fract = fract(g_uv) - 0.5;
		vec2 g_rnd = hash22_glass(g_id);
		if (g_rnd.x < wear_density) {
			float g_angle = (g_rnd.y - 0.5) * 2.8;
			vec2 g_dir = vec2(cos(g_angle), sin(g_angle));
			vec2 g_norm = vec2(-g_dir.y, g_dir.x);
			float g_along = dot(g_fract, g_dir);
			float g_perp = abs(dot(g_fract, g_norm));
			glass_scratch = step(abs(g_along), 0.12 + g_rnd.x * 0.18) * step(g_perp, 0.012);
		}
	}

	// 5. Tentukan Warna Tinta 1-Bit:
	// - Pinggir paling luar = HITAM PEKAT (Outline siluet agar terbaca tegas di dinding terang)
	// - Pinggir dalam, pantulan diagonal, dan pendaran = PUTIH BERSIH
	vec3 ink_color = vec3(1.0);
	if (is_outer_rim > 0.5) {
		ink_color = vec3(0.0);
	}
	ALBEDO = ink_color;

	// 6. Opacity / Alpha:
	// - Outline hitam luar: 0.95 (garis tegas)
	// - Kilau putih dalam: 0.85
	// - Garis kilau diagonal manga: 0.70
	// - Badan kaca transparan: base_alpha (0.18) agar isi spesimen di dalam tetap terlihat jelas
	float rim_alpha = max(is_outer_rim * 0.95, is_inner_rim * 0.85);
	float final_alpha = clamp(base_alpha + rim_alpha + (comic_sheen * 0.65) + vert_sheen + (glass_scratch * 0.85), 0.0, 0.98);
	ALPHA = final_alpha;

	ROUGHNESS = 0.05;
	METALLIC = 0.0;

	// 7. Reaksi Gelombang Ekolokasi Suara (Ketukan Tap)
	EMISSION = vec3(0.0);
	if (abs(tap_radius) > 0.05) {
		float dist = distance(world_pos, tap_origin);
		bool is_expanding = (tap_radius > 0.0);
		float current_r = is_expanding ? tap_radius : floor(abs(tap_radius));
		float global_fade = is_expanding ? 1.0 : fract(abs(tap_radius));

		if (dist <= current_r + 0.3) {
			float wave_ring = smoothstep(0.25, 0.0, abs(dist - current_r));
			float wave_afterglow = 0.0;
			float delta = current_r - dist;
			if (delta >= 0.0 && delta <= 3.0) {
				wave_afterglow = pow(1.0 - (delta / 3.0), 1.5) * 0.5;
			}
			float echo = clamp(wave_ring + wave_afterglow, 0.0, 1.0) * global_fade;
			EMISSION = vec3(echo * echo_intensity * (fresnel * 1.5 + 0.4));
		}
	}
}

void light() {
	// Reaksi terhadap Senter Pemain:
	float n_dot_l = max(dot(NORMAL, LIGHT), 0.0);
	if (n_dot_l > 0.02) {
		float flash_boost = smoothstep(0.02, 0.5, n_dot_l);
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (ALBEDO * flash_boost * 1.5);
	}
}
