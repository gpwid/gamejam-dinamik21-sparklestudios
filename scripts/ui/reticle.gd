@tool
extends Control
class_name Reticle

enum StealthState {
	NORMAL,
	DANGER_INCOMING,
	HOLDING_BREATH,
	SAFE_TO_BREATHE,
	SAFE_HOLDING_BREATH
}

@export var dot_radius: float = 2.0:
	set(val):
		dot_radius = val
		queue_redraw()

@export var dot_color: Color = Color(1.0, 1.0, 1.0, 0.9):
	set(val):
		dot_color = val
		queue_redraw()

@export var outline_width: float = 1.0:
	set(val):
		outline_width = val
		queue_redraw()

@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.65):
	set(val):
		outline_color = val
		queue_redraw()

var stealth_state: StealthState = StealthState.NORMAL
var breath_stamina_ratio: float = 1.0
var stealth_pulse: float = 0.0
var safe_timer: float = 0.0
var safe_duration: float = 1.8
var danger_snap: float = 0.0
var is_interact_hover: bool = false
var interact_scale: float = 1.0

func set_interact_hover(hover: bool) -> void:
	if is_interact_hover != hover:
		is_interact_hover = hover
		queue_redraw()

func _process(delta: float) -> void:
	stealth_pulse += delta * 7.0

	var target_scale: float = 1.9 if is_interact_hover else 1.0
	if not is_equal_approx(interact_scale, target_scale):
		interact_scale = move_toward(interact_scale, target_scale, delta * 9.0)
		queue_redraw()

	if danger_snap > 0.0:
		danger_snap = move_toward(danger_snap, 0.0, delta * 5.5)
		queue_redraw()

	if safe_timer > 0.0:
		safe_timer -= delta
		if safe_timer <= 0.0:
			safe_timer = 0.0
			if stealth_state == StealthState.SAFE_TO_BREATHE:
				stealth_state = StealthState.NORMAL
		queue_redraw()
	elif stealth_state != StealthState.NORMAL:
		queue_redraw()

func set_stealth_state(new_state: StealthState, stamina_ratio: float = 1.0) -> void:
	breath_stamina_ratio = clampf(stamina_ratio, 0.0, 1.0)

	# Transisi dari kondisi bahaya ke aman otomatis memicu animasi riak/sinyal aman
	if (stealth_state == StealthState.HOLDING_BREATH or stealth_state == StealthState.DANGER_INCOMING) and (new_state == StealthState.SAFE_HOLDING_BREATH or new_state == StealthState.SAFE_TO_BREATHE):
		safe_timer = safe_duration

	if new_state == StealthState.DANGER_INCOMING:
		if stealth_state != StealthState.DANGER_INCOMING:
			danger_snap = 1.0
		stealth_state = StealthState.DANGER_INCOMING
		queue_redraw()
		return

	if new_state == StealthState.SAFE_TO_BREATHE:
		if safe_timer <= 0.0:
			safe_timer = safe_duration
		stealth_state = StealthState.SAFE_TO_BREATHE
		queue_redraw()
		return

	if new_state == StealthState.HOLDING_BREATH:
		stealth_state = StealthState.HOLDING_BREATH
		queue_redraw()
		return

	if new_state == StealthState.SAFE_HOLDING_BREATH:
		stealth_state = StealthState.SAFE_HOLDING_BREATH
		queue_redraw()
		return

	# NORMAL
	stealth_state = StealthState.NORMAL
	queue_redraw()

func _draw() -> void:
	# 1. Base Center Reticle Dot (Membesar saat mengarah ke objek interactable)
	var cur_dot_r: float = dot_radius * interact_scale
	if outline_width > 0.0:
		draw_circle(Vector2.ZERO, cur_dot_r + outline_width, outline_color)
	draw_circle(Vector2.ZERO, cur_dot_r, dot_color)

	# 2. Sinyal Aman / Safe Pulse: Dual-ripple gelombang ekspansi putih (~1.8 detik)
	# Digunakan saat transisi aman ketika TIDAK sedang menahan shift
	if safe_timer > 0.0 and stealth_state != StealthState.SAFE_HOLDING_BREATH:
		var safe_progress: float = 1.0 - (safe_timer / safe_duration)
		# Ripple Utama
		var ripple_radius: float = 8.0 + safe_progress * 18.0
		var ripple_alpha: float = (1.0 - safe_progress) * 0.85
		var ripple_col := Color(1.0, 1.0, 1.0, ripple_alpha)
		draw_arc(Vector2.ZERO, ripple_radius, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, ripple_alpha * 0.5), 3.0)
		draw_arc(Vector2.ZERO, ripple_radius, 0.0, TAU, 32, ripple_col, 1.8)

		# Ripple Kedua yang menyusul di belakang
		if safe_progress > 0.15:
			var p2: float = (safe_progress - 0.15) / 0.85
			var r2: float = 8.0 + p2 * 14.0
			var a2: float = (1.0 - p2) * 0.55
			draw_arc(Vector2.ZERO, r2, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, a2), 1.2)

	# 3. Bentuk Peringatan Bahaya: 4 Corner Brackets / Siku-Siku [ · ] dengan Scale Pop-In Responsif
	if stealth_state == StealthState.DANGER_INCOMING:
		var snap_scale: float = danger_snap * 9.0
		var pulse_scale: float = 14.0 + snap_scale + sin(stealth_pulse) * 1.5
		var bracket_alpha: float = 0.85 + 0.15 * sin(stealth_pulse)
		var bracket_col := Color(1.0, 1.0, 1.0, bracket_alpha)
		var dark_outline := Color(0.0, 0.0, 0.0, 0.7 * bracket_alpha)
		var arm_len: float = 4.5 + danger_snap * 2.0
		var bracket_width: float = 1.6 + danger_snap * 1.0

		# Outline gelap di belakang siku-siku agar kontras tajam
		_draw_corner_brackets(pulse_scale, arm_len, dark_outline, bracket_width + 1.5)
		# Siku-siku putih bersih
		_draw_corner_brackets(pulse_scale, arm_len, bracket_col, bracket_width)

	# 4. Bentuk Menahan Napas Saat Bahaya: Busur Lingkaran Stamina yang Berkurang ( · )
	elif stealth_state == StealthState.HOLDING_BREATH:
		# Track lingkaran tipis di belakang
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, 0.4), 3.0)
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.2), 1.5)

		var arc_alpha: float = 0.95
		# Strobe pulse saat stamina sekarat (< 35%)
		if breath_stamina_ratio < 0.35:
			if sin(stealth_pulse * 2.5) < 0.0:
				arc_alpha = 0.25

		var start_ang: float = -PI * 0.5
		var end_ang: float = start_ang + (TAU * breath_stamina_ratio)
		if breath_stamina_ratio > 0.01:
			var arc_col := Color(1.0, 1.0, 1.0, arc_alpha)
			draw_arc(Vector2.ZERO, 10.0, start_ang, end_ang, 32, Color(0.0, 0.0, 0.0, 0.6 * arc_alpha), 3.5)
			draw_arc(Vector2.ZERO, 10.0, start_ang, end_ang, 32, arc_col, 2.0)

		# Jika kondisi di luar sudah AMAN saat pemain masih menahan Shift:
		if safe_timer > 0.0:
			var safe_ratio: float = safe_timer / safe_duration
			var halo_alpha: float = clampf(safe_ratio * 0.8, 0.2, 0.8)
			draw_arc(Vector2.ZERO, 14.5, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, halo_alpha), 1.6)

	# 5. Bentuk Menahan Shift Saat Monster Sudah Jauh / Aman: Lingkaran Penuh yang "Bernapas" Tenang ( ○ )
	elif stealth_state == StealthState.SAFE_HOLDING_BREATH:
		# Radius berdenyut tenang seirama siklus napas santai (~0.35 Hz)
		var breath_pulse_r: float = 10.5 + sin(stealth_pulse * 0.35) * 1.4
		var breath_alpha: float = 0.88 + 0.12 * sin(stealth_pulse * 0.35)
		var ring_col := Color(1.0, 1.0, 1.0, breath_alpha)

		# Outline gelap + lingkaran putih utuh (penuh 360 derajat, tidak berkurang)
		draw_arc(Vector2.ZERO, breath_pulse_r, 0.0, TAU, 36, Color(0.0, 0.0, 0.0, 0.65 * breath_alpha), 3.2)
		draw_arc(Vector2.ZERO, breath_pulse_r, 0.0, TAU, 36, ring_col, 1.8)

		# Tanda Khusus: Jika monster baru saja selesai investigasi / sinyal aman aktif (safe_timer > 0.0):
		if safe_timer > 0.0:
			var safe_p: float = 1.0 - (safe_timer / safe_duration)
			var safe_fade: float = 1.0 - safe_p

			# Riak ekspansi lembut keluar dari lingkaran bernapas
			var ripple_r: float = breath_pulse_r + safe_p * 15.0
			var ripple_a: float = safe_fade * 0.8
			draw_arc(Vector2.ZERO, ripple_r, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, ripple_a * 0.45), 2.8)
			draw_arc(Vector2.ZERO, ripple_r, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, ripple_a), 1.6)

			# 4 Ticks / Aksen penjuru mata angin pada lingkaran bernapas (Konfirmasi tegas: INVESTIGASI SELESAI / AMAN)
			var tick_dist_inner: float = breath_pulse_r + 1.8
			var tick_dist_outer: float = breath_pulse_r + 4.8 + safe_fade * 1.5
			var tick_col := Color(1.0, 1.0, 1.0, safe_fade * 0.9)
			var tick_outline := Color(0.0, 0.0, 0.0, safe_fade * 0.6)

			for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
				var dir := Vector2(cos(angle), sin(angle))
				# Outline hitam
				draw_line(dir * tick_dist_inner, dir * tick_dist_outer, tick_outline, 2.6)
				# Garis putih
				draw_line(dir * tick_dist_inner, dir * tick_dist_outer, tick_col, 1.4)

func _draw_corner_brackets(radius: float, arm_len: float, col: Color, width: float) -> void:
	# Top-Left corner
	draw_line(Vector2(-radius, -radius + arm_len), Vector2(-radius, -radius), col, width)
	draw_line(Vector2(-radius, -radius), Vector2(-radius + arm_len, -radius), col, width)

	# Top-Right corner
	draw_line(Vector2(radius - arm_len, -radius), Vector2(radius, -radius), col, width)
	draw_line(Vector2(radius, -radius), Vector2(radius, -radius + arm_len), col, width)

	# Bottom-Right corner
	draw_line(Vector2(radius, radius - arm_len), Vector2(radius, radius), col, width)
	draw_line(Vector2(radius, radius), Vector2(radius - arm_len, radius), col, width)

	# Bottom-Left corner
	draw_line(Vector2(-radius + arm_len, radius), Vector2(-radius, radius), col, width)
	draw_line(Vector2(-radius, radius), Vector2(-radius, radius - arm_len), col, width)
