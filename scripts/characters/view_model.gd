extends CanvasLayer
class_name ViewModel

@export_group("Hand Sprites")
@export var sprite_idle: Texture2D = preload("res://assets/sprites/righthand_idle.png")
@export var sprite_before_snap: Texture2D = preload("res://assets/sprites/righthand_before_snap.png")
@export var sprite_after_snap: Texture2D = preload("res://assets/sprites/righthand_after_snap.png")

@onready var hand_container: Control = $HandContainer
@onready var hand_texture: TextureRect = $HandContainer/HandTexture
@onready var exhaustion_vignette: ColorRect = get_node_or_null("ExhaustionVignette")

var snap_tween: Tween
var is_snapping: bool = false

# Warna visualisasi senter
const COLOR_LIT: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_DIM: Color = Color(0.25, 0.25, 0.3, 1.0)
const COLOR_OVERHEAT: Color = Color(0.9, 0.2, 0.2, 1.0)

var is_flashlight_lit: bool = false
var is_overheated_visual: bool = false

# Kelelahan (Stamina habis / Exhaustion)
var is_exhausted: bool = false
var exhaustion_intensity: float = 0.0

# Pengaturan Bobbing Jalan & Bernapas (Idle)
# 4.3 rad/s setara periode ~1.46 detik, seirama dengan siklus tarikan napas audio idle_breathing.wav
const BREATH_FREQUENCY: float = 4.3
const BREATH_AMPLITUDE_PX: float = 4.0

const WALK_BOB_FREQ_WALK: float = 10.0
const WALK_BOB_FREQ_SPRINT: float = 14.0
const WALK_BOB_AMP_X: float = 4.0
const WALK_BOB_AMP_Y: float = 6.0

var is_moving: bool = false
var is_sprinting: bool = false
var is_idle: bool = true
var breath_time: float = 0.0
var walk_bob_time: float = 0.0
var current_bob: Vector2 = Vector2.ZERO

func _ready() -> void:
	if hand_texture:
		if sprite_idle:
			hand_texture.texture = sprite_idle
		_update_pivot()
		hand_texture.resized.connect(_update_pivot)
	update_flashlight_visual(false)

func _update_pivot() -> void:
	if is_instance_valid(hand_texture):
		# Titik tumpu rotasi & skala di pergelangan tangan (kanan bawah)
		hand_texture.pivot_offset = hand_texture.size * Vector2(0.75, 0.95)

func _process(delta: float) -> void:
	# Update efek visual kelelahan (Vignette merah layar & tint tangan)
	var target_intensity: float = 1.0 if is_exhausted else 0.0
	exhaustion_intensity = lerpf(exhaustion_intensity, target_intensity, clampf(4.0 * delta, 0.0, 1.0))

	if is_instance_valid(exhaustion_vignette) and exhaustion_vignette.material is ShaderMaterial:
		(exhaustion_vignette.material as ShaderMaterial).set_shader_parameter("vignette_intensity", exhaustion_intensity)

	_update_hand_modulate()

	if not is_instance_valid(hand_texture):
		return
	if is_snapping:
		return

	var target_bob: Vector2 = Vector2.ZERO

	if is_moving:
		var freq: float = WALK_BOB_FREQ_SPRINT if is_sprinting else WALK_BOB_FREQ_WALK
		var mult: float = 1.35 if is_sprinting else 1.0
		walk_bob_time += freq * delta
		target_bob.x = cos(walk_bob_time * 0.5) * WALK_BOB_AMP_X * mult
		target_bob.y = -abs(sin(walk_bob_time)) * WALK_BOB_AMP_Y * mult
	else:
		walk_bob_time = 0.0
		breath_time += BREATH_FREQUENCY * delta
		target_bob.x = cos(breath_time * 0.5) * 1.5
		# Bobbing naik-turun halus sinkron dengan tarikan dan hembusan napas
		target_bob.y = (1.0 - cos(breath_time)) * 0.5 * BREATH_AMPLITUDE_PX

	current_bob = current_bob.lerp(target_bob, clampf(10.0 * delta, 0.0, 1.0))
	hand_texture.position = current_bob

func set_idle(idle: bool) -> void:
	is_idle = idle
	if is_idle:
		is_moving = false

func update_movement(moving: bool, sprinting: bool, _speed: float, _delta: float) -> void:
	is_moving = moving
	is_sprinting = sprinting
	is_idle = not moving

func set_exhausted(exhausted: bool) -> void:
	is_exhausted = exhausted

func update_flashlight_visual(is_on: bool) -> void:
	is_flashlight_lit = is_on
	_update_hand_modulate()

func play_overheat_warning(is_overheated: bool) -> void:
	is_overheated_visual = is_overheated
	_update_hand_modulate()

func _update_hand_modulate() -> void:
	if not is_instance_valid(hand_texture):
		return

	var base_col: Color = COLOR_DIM
	if is_overheated_visual:
		base_col = COLOR_OVERHEAT
	elif is_flashlight_lit:
		base_col = COLOR_LIT

	if exhaustion_intensity > 0.001:
		# Denyut kemerahan lembut HANYA pada kanal warna RGB, Alpha DIKUNCI 1.0 (tetap 100% solid)
		var pulse: float = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.0043)
		var red_tint := Color(
			base_col.r,
			base_col.g * lerpf(0.45, 0.75, pulse),
			base_col.b * lerpf(0.45, 0.75, pulse),
			1.0
		)
		var final_col: Color = base_col.lerp(red_tint, exhaustion_intensity)
		final_col.a = 1.0 # Menjamin sprite tangan 100% solid tanpa transparansi
		hand_texture.modulate = final_col
	else:
		base_col.a = 1.0
		hand_texture.modulate = base_col

func play_tap_recoil() -> void:
	# Jika sedang menjalankan snap animation, recoil sudah ditangani oleh Tween snap
	if is_snapping or not is_instance_valid(hand_texture):
		return
	if snap_tween and snap_tween.is_valid():
		snap_tween.kill()

	snap_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	snap_tween.tween_property(hand_texture, "position:y", current_bob.y + 20.0, 0.08)
	snap_tween.tween_property(hand_texture, "position:y", current_bob.y, 0.16)

# ==============================================================================
# ALUR ANIMASI SNAP JENTIK JARI (TWEEN ECHOLOCATION)
# ==============================================================================
func play_snap_animation(on_snap: Callable = Callable(), on_complete: Callable = Callable()) -> void:
	if not is_instance_valid(hand_texture):
		if on_snap.is_valid():
			on_snap.call()
		if on_complete.is_valid():
			on_complete.call()
		return

	is_snapping = true

	if snap_tween and snap_tween.is_valid():
		snap_tween.kill()

	# 1. Ganti sprite ke righthand_before_snap.png (posisi siap jentik jari)
	if sprite_before_snap:
		hand_texture.texture = sprite_before_snap

	snap_tween = create_tween()

	# --- FASE 1: ANTICIPATION (Angkat posisi tangan ke atas & agak miring secara cepat) ---
	snap_tween.tween_property(hand_texture, "position", Vector2(-12.0, -32.0), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "rotation", deg_to_rad(-6.0), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "scale", Vector2(0.97, 1.05), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Jeda singkat sebelum jentikan
	snap_tween.chain().tween_interval(0.04)

	# --- FASE 2: SNAP & RECOIL/POP (Ganti sprite ke after_snap bersamaan pemicuan gelombang echolocation) ---
	snap_tween.chain().tween_callback(func():
		if sprite_after_snap:
			hand_texture.texture = sprite_after_snap
		if on_snap.is_valid():
			on_snap.call()
	)

	# Hentakan snappy ke bawah (recoil / pop)
	snap_tween.chain().tween_property(hand_texture, "position", Vector2(10.0, 22.0), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "rotation", deg_to_rad(7.0), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "scale", Vector2(1.08, 0.94), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# --- FASE 3: RETURN TO IDLE (Kembalikan mulus ke posisi, rotasi, dan skala awal) ---
	snap_tween.chain().tween_property(hand_texture, "position", Vector2.ZERO, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Selesai: kembalikan ke sprite idle & buka kunci snapping
	snap_tween.chain().tween_callback(func():
		if sprite_idle:
			hand_texture.texture = sprite_idle
		is_snapping = false
		current_bob = Vector2.ZERO
		if on_complete.is_valid():
			on_complete.call()
	)
