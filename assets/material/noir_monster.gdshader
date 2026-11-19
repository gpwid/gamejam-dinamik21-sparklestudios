shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform bool use_texture = false;
uniform float tex_brightness : hint_range(0.5, 4.0) = 1.6;
uniform float tex_contrast : hint_range(0.5, 3.0) = 1.25;
uniform float jumpscare_lit : hint_range(0.0, 1.0) = 0.0;

uniform vec3 body_color : source_color = vec3(1.0, 1.0, 1.0);
uniform bool is_face = false;

// Pengaturan Mata (Aktif jika is_face = true dan use_texture = false)
uniform vec2 eye_left = vec2(0.31, 0.42);
uniform vec2 eye_right = vec2(0.64, 0.42);
uniform vec2 eye_size = vec2(0.045, 0.065);
uniform float eye_slant_deg = 15.0;
uniform float socket_mult : hint_range(1.2, 3.0) = 1.85;
uniform vec3 eye_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 socket_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float eye_glow : hint_range(1.0, 10.0) = 4.5;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.2;

void fragment() {
	if (use_texture) {
		vec3 tex = texture(albedo_tex, UV).rgb;
		tex = clamp((tex - 0.08) * tex_contrast + 0.08, vec3(0.0), vec3(1.0)) * tex_brightness;
		ALBEDO = clamp(tex, vec3(0.0), vec3(1.0));
		EMISSION = ALBEDO * jumpscare_lit * 0.45;
	} else if (!is_face) {
		// Tubuh: putih bersih ala komik noir 1-bit
		ALBEDO = body_color;
		EMISSION = vec3(0.0);
	} else {
		vec2 uv = UV;

		// Rotasi sudut kemiringan mata (tatapan tajam monster)
		float rad = radians(eye_slant_deg);
		float cos_a = cos(rad);
		float sin_a = sin(rad);

		// Mata kiri
		vec2 dlu = uv - eye_left;
		vec2 rot_l = vec2(dlu.x * cos_a - dlu.y * sin_a, dlu.x * sin_a + dlu.y * cos_a);
		float dist_l = length(rot_l / eye_size);

		// Mata kanan (simetris berlawanan)
		vec2 dru = uv - eye_right;
		vec2 rot_r = vec2(dru.x * cos_a + dru.y * sin_a, -dru.x * sin_a + dru.y * cos_a);
		float dist_r = length(rot_r / eye_size);

		float min_dist = min(dist_l, dist_r);

		// 1. Pupil Mata Bersinar
		float eye_pupil = 1.0 - smoothstep(0.7, 1.0, min_dist);

		// 2. Rongga Mata Gelap (Agar pupil putih kontras tajam di atas wajah putih)
		float eye_socket = 1.0 - smoothstep(socket_mult * 0.85, socket_mult, min_dist);

		vec3 col = body_color;
		// Blend rongga mata hitam
		col = mix(col, socket_color, eye_socket);
		// Blend pupil mata
		col = mix(col, eye_color, eye_pupil);

		ALBEDO = col;

		// Emisi mata berpendar halus
		float pulse = 0.88 + 0.12 * sin(TIME * pulse_speed);
		EMISSION = eye_color * (eye_pupil * eye_glow * pulse);
	}
}

void light() {
	// Antisipasi model low-poly: gunakan Half-Lambert wrapping agar poligon samping
	// tidak tiba-tiba terpotong hitam pekat akibat orientasi normal facet segitiga.
	float NdotL = dot(NORMAL, LIGHT);
	float wrap_light = max(0.0, NdotL * 0.5 + 0.5);

	// Deteksi pencahayaan dari spotlight & shadow map
	float light_intensity = max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b));
	float in_atten = step(0.02, ATTENUATION) * step(0.01, light_intensity);

	if (use_texture) {
		// Permukaan bertekstur (wajah & organ): terlihat jelas saat terkena cahaya, gelap total saat mati lampu
		float lit = in_atten * mix(0.75, 1.0, step(0.1, wrap_light));
		DIFFUSE_LIGHT += ALBEDO * lit;
	} else if (is_face) {
		// Wajah selalu tampak jelas di dalam sorotan lampu
		float lit = in_atten * step(0.08, wrap_light);
		DIFFUSE_LIGHT += ALBEDO * max(lit, 0.7);
	} else {
		// Tubuh: putih solid di sisi yang terkena sinar, hanya gelap jika membelakangi total
		float lit = in_atten * step(0.12, wrap_light);
		DIFFUSE_LIGHT += ALBEDO * lit;
	}
}
