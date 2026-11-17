shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

uniform float outline_width : hint_range(0.0, 0.05, 0.001) = 0.016;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void vertex() {
	// Inverted Hull: dorong vertex sepanjang normal untuk membentuk siluet tebal di belakang mesh
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
