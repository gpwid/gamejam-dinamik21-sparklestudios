shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled;

uniform sampler2D screen_texture : source_color, hint_screen_texture, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

global uniform vec3 tap_origin;
global uniform float tap_radius;

uniform float outline_width : hint_range(0.5, 3.0, 0.5) = 1.0;
uniform float depth_edge_threshold : hint_range(0.01, 0.5, 0.005) = 0.08;
uniform float normal_edge_threshold : hint_range(0.05, 1.0, 0.05) = 0.20;

// Disinkronkan dari player.gd agar garis putih area gelap hanya muncul di dalam kerucut senter
uniform bool flashlight_on = false;
uniform vec3 flashlight_view_pos = vec3(0.3, -0.351, 0.0);
uniform vec3 flashlight_view_dir = vec3(0.0, 0.0, -1.0);
uniform float flashlight_cos_angle = 0.7071;
uniform float flashlight_range = 25.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 get_view_pos(vec2 uv, mat4 inv_proj) {
	float raw_depth = texture(depth_texture, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
#endif
	vec4 view = inv_proj * vec4(ndc, 1.0);
	return view.xyz / view.w;
}

float get_lum(vec2 uv) {
	vec3 c = texture(screen_texture, uv).rgb;
	return max(c.r, max(c.g, c.b));
}

vec3 safe_normalize(vec3 v) {
	float len = length(v);
	return len > 0.00001 ? (v / len) : vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = (1.0 / VIEWPORT_SIZE) * outline_width;

	vec3 screen_col = texture(screen_texture, uv).rgb;
	float lum_c = max(screen_col.r, max(screen_col.g, screen_col.b));

	vec2 uv_l = clamp(uv - vec2(px.x, 0.0), vec2(0.0), vec2(1.0));
	vec2 uv_r = clamp(uv + vec2(px.x, 0.0), vec2(0.0), vec2(1.0));
	vec2 uv_u = clamp(uv - vec2(0.0, px.y), vec2(0.0), vec2(1.0));
	vec2 uv_d = clamp(uv + vec2(0.0, px.y), vec2(0.0), vec2(1.0));

	vec3 p_c = get_view_pos(uv, INV_PROJECTION_MATRIX);
	vec3 p_l = get_view_pos(uv_l, INV_PROJECTION_MATRIX);
	vec3 p_r = get_view_pos(uv_r, INV_PROJECTION_MATRIX);
	vec3 p_u = get_view_pos(uv_u, INV_PROJECTION_MATRIX);
	vec3 p_d = get_view_pos(uv_d, INV_PROJECTION_MATRIX);

	float d_c = max(-p_c.z, 0.01);
	float d_l = max(-p_l.z, 0.01);
	float d_r = max(-p_r.z, 0.01);
	float d_u = max(-p_u.z, 0.01);
	float d_d = max(-p_d.z, 0.01);

	// Laplacian pada 1/z bernilai 0 pada bidang datar miring sekalipun, dan melonjak hanya pada siluet
	float lap_x = d_c / d_l + d_c / d_r - 2.0;
	float lap_y = d_c / d_u + d_c / d_d - 2.0;
	float pos_lap = max(lap_x, lap_y);
	float neg_lap = max(-lap_x, -lap_y);
	float max_lap = max(pos_lap, neg_lap);

	// Sudut patahan 3D di tempat kedalaman kontinu (mis. kaki meja bertemu lantai / sudut gelap)
	float crease_x = 1.0 - dot(safe_normalize(p_c - p_l), safe_normalize(p_r - p_c));
	float crease_y = 1.0 - dot(safe_normalize(p_c - p_u), safe_normalize(p_d - p_c));
	float crease = max(crease_x, crease_y);
	bool is_crease = (max_lap <= depth_edge_threshold) && (crease > normal_edge_threshold) && (d_c < 18.0);

	vec3 final_col = screen_col;
	bool in_spot = false;
	if (flashlight_on) {
		vec3 to_frag = p_c - flashlight_view_pos;
		float dist = length(to_frag);
		float cone_dot = dot(safe_normalize(to_frag), safe_normalize(flashlight_view_dir));
		in_spot = (dist <= flashlight_range) && (cone_dot >= flashlight_cos_angle - 0.02);
	}

	if (lum_c > 0.15) {
		// Area terang di dalam senter: garis tepi siluet & sudut berwarna HITAM (jangan hapus garis putih echolocation di luar senter)
		if (in_spot && (pos_lap > depth_edge_threshold || is_crease)) {
			final_col = vec3(0.0);
		}
	} else {
		if (in_spot) {
			// Area gelap di dalam kerucut senter: garis PUTIH untuk objek gelap-di-atas-gelap & sudut gelap
			float max_neighbor_lum = max(max(get_lum(uv_l), get_lum(uv_r)), max(get_lum(uv_u), get_lum(uv_d)));
			bool dark_over_dark = (max_neighbor_lum <= 0.15) && (neg_lap > depth_edge_threshold);
			if (dark_over_dark || is_crease) {
				final_col = vec3(1.0);
			}
		}

		// Garis siluet & sudut putih saat echolocation aktif (termasuk sisi luar kotak/meja)
		if (abs(tap_radius) > 0.05 && d_c < 50.0) {
			vec3 world_pos = (INV_VIEW_MATRIX * vec4(p_c, 1.0)).xyz;
			float tap_dist = distance(world_pos, tap_origin);
			bool is_expanding = (tap_radius > 0.0);
			float current_r = is_expanding ? tap_radius : floor(abs(tap_radius));
			float global_fade = is_expanding ? 1.0 : fract(abs(tap_radius));

			if (tap_dist <= current_r + 0.25) {
				float revealed_area = 1.0 - smoothstep(current_r - 0.4, current_r + 0.2, tap_dist);
				if (neg_lap > depth_edge_threshold || is_crease) {
					final_col = max(final_col, vec3(revealed_area * global_fade));
				}
			}
		}
	}

	ALBEDO = final_col;
}
