extends CanvasLayer
class_name ViewModel

@export_group("Right Hand Sprites (Echolocation)")
@export var sprite_idle: Texture2D = preload("res://assets/sprites/righthand_idle.png")
@export var sprite_before_snap: Texture2D = preload("res://assets/sprites/righthand_before_snap.png")
@export var sprite_after_snap: Texture2D = preload("res://assets/sprites/righthand_after_snap.png")

@export_group("Left Hand Sprites (Flashlight)")
@export var sprite_flashlight: Texture2D = preload("res://assets/sprites/lefthand_flashlight.png")
@export var sprite_flashlight_click: Texture2D = preload("res://assets/sprites/lefthand_flashlight_click.png")

@onready var right_hand_container: Control = get_node_or_null("RightHandContainer")
@onready var hand_container: Control = right_hand_container
@onready var hand_texture: TextureRect = get_node_or_null("RightHandContainer/HandTexture")
@onready var right_hand_texture: TextureRect = hand_texture
@onready var left_hand_container: Control = get_node_or_null("LeftHandContainer")
@onready var left_hand_texture: TextureRect = get_node_or_null("LeftHandContainer/LeftHandTexture")
@onready var exhaustion_blur: ColorRect = get_node_or_null("ExhaustionVignette")
@onready var prompt_label: Label = get_node_or_null("PromptLabel")

var snap_tween: Tween
var is_snapping: bool = false

var click_tween: Tween
var is_clicking: bool = false

var prompt_tween: Tween
var jolt_tween: Tween

# Warna visualisasi senter
const COLOR_LIT: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_DIM: Color = Color(0.25, 0.25, 0.3, 1.0)
const COLOR_OVERHEAT: Color = Color(0.9, 0.2, 0.2, 1.0)

var is_flashlight_lit: bool = false
var is_overheated_visual: bool = false
var current_hand_color: Color = COLOR_DIM

# Kelelahan & Pandangan Buram (Screen Blur)
var is_exhausted: bool = false
var is_recovering_from_exhaustion: bool = false
var blur_intensity: float = 0.0
var target_blur_intensity: float = 0.0

# Pengaturan Bobbing Jalan & Bernapas (Idle)
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
var walk_bob_weight: float = 0.0
var current_bob: Vector2 = Vector2.ZERO
var current_left_bob: Vector2 = Vector2.ZERO

# Sistem Menahan Napas & Zona Monster
var is_holding_breath: bool = false
var hold_breath_stamina_ratio: float = 1.0
var fear_tremor_intensity: float = 0.0
var heartbeat_pulse: float = 0.0
var current_static_intensity: float = 0.0
var prompt_is_visible: bool = false

func _ready() -> void:
	if hand_texture:
		if sprite_idle:
			hand_texture.texture = sprite_idle
		_update_pivot()
		hand_texture.resized.connect(_update_pivot)

	if left_hand_texture:
		if sprite_flashlight:
			left_hand_texture.texture = sprite_flashlight
		_update_pivot()
		left_hand_texture.resized.connect(_update_pivot)

	if prompt_label:
		prompt_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	update_flashlight_visual(false)

func _update_pivot() -> void:
	if is_instance_valid(hand_texture):
		hand_texture.pivot_offset = hand_texture.size * Vector2(0.75, 0.95)
	if is_instance_valid(left_hand_texture):
		left_hand_texture.pivot_offset = left_hand_texture.size * Vector2(0.25, 0.95)

func _process(delta: float) -> void:
	# 1. Update efek visual kelelahan (Screen Blur dinamis & halus)
	var dynamic_target_blur: float = target_blur_intensity
	if is_holding_breath and hold_breath_stamina_ratio < 0.35:
		var low_stam_factor: float = (0.35 - hold_breath_stamina_ratio) / 0.35
		dynamic_target_blur = maxf(dynamic_target_blur, low_stam_factor * 0.45)

	blur_intensity = lerpf(blur_intensity, dynamic_target_blur, clampf(5.0 * delta, 0.0, 1.0))
	if dynamic_target_blur == 0.0 and blur_intensity < 0.005:
		blur_intensity = 0.0

	# 2. Denyut 1-Bit White Static Vignette seirama detak jantung
	heartbeat_pulse = move_toward(heartbeat_pulse, 0.0, 3.0 * delta)
	var target_static: float = 0.0
	if fear_tremor_intensity > 0.001:
		target_static = fear_tremor_intensity * (0.2 + 0.65 * heartbeat_pulse)
	if is_holding_breath and hold_breath_stamina_ratio < 0.35:
		var low_stam: float = (0.35 - hold_breath_stamina_ratio) / 0.35
		var low_stam_static: float = (0.25 + 0.75 * heartbeat_pulse) * (0.35 + 0.65 * low_stam)
		target_static = maxf(target_static, low_stam_static)

	current_static_intensity = lerpf(current_static_intensity, target_static, clampf(10.0 * delta, 0.0, 1.0))
	if target_static == 0.0 and current_static_intensity < 0.005:
		current_static_intensity = 0.0

	if is_instance_valid(exhaustion_blur) and exhaustion_blur.material is ShaderMaterial:
		var mat := exhaustion_blur.material as ShaderMaterial
		mat.set_shader_parameter("blur_intensity", blur_intensity)
		mat.set_shader_parameter("static_intensity", current_static_intensity)

	_update_hand_modulate(delta)

	if not is_instance_valid(hand_texture) and not is_instance_valid(left_hand_texture):
		return

	# 3. Gerak tangan Idle Breathing / Berjalan / Menahan Napas
	if not is_holding_breath:
		breath_time += BREATH_FREQUENCY * delta
		var idle_bob := Vector2(
			cos(breath_time * 0.5) * 1.5,
			(1.0 - cos(breath_time)) * 0.5 * BREATH_AMPLITUDE_PX
		)

		var freq: float = WALK_BOB_FREQ_SPRINT if is_sprinting else WALK_BOB_FREQ_WALK
		var mult: float = 1.35 if is_sprinting else 1.0
		walk_bob_time += freq * delta
		var walk_bob := Vector2(
			cos(walk_bob_time * 0.5) * WALK_BOB_AMP_X * mult,
			-abs(sin(walk_bob_time)) * WALK_BOB_AMP_Y * mult
		)

		var target_weight: float = 1.0 if is_moving else 0.0
		walk_bob_weight = lerpf(walk_bob_weight, target_weight, clampf(6.0 * delta, 0.0, 1.0))

		var target_bob: Vector2 = idle_bob.lerp(walk_bob, walk_bob_weight)
		current_bob = current_bob.lerp(target_bob, clampf(10.0 * delta, 0.0, 1.0))

		var target_left_bob := Vector2(-target_bob.x, target_bob.y)
		current_left_bob = current_left_bob.lerp(target_left_bob, clampf(10.0 * delta, 0.0, 1.0))
	else:
		# Saat menahan napas: idle bobbing beku/diam
		current_bob = current_bob.lerp(Vector2.ZERO, clampf(10.0 * delta, 0.0, 1.0))
		current_left_bob = current_left_bob.lerp(Vector2.ZERO, clampf(10.0 * delta, 0.0, 1.0))

	# 4. Fear Tremor Jitter (getaran ketakutan di zona peringatan atau saat stamina sekarat)
	var tremor_amp: float = fear_tremor_intensity * 2.8
	if is_holding_breath and hold_breath_stamina_ratio < 0.35:
		var low_stam_factor: float = (0.35 - hold_breath_stamina_ratio) / 0.35
		tremor_amp += low_stam_factor * 5.5

	var jitter := Vector2.ZERO
	if tremor_amp > 0.05:
		jitter = Vector2(randf_range(-tremor_amp, tremor_amp), randf_range(-tremor_amp, tremor_amp))

	# Terapkan ke tangan kanan jika tidak sedang animasi snap
	if is_instance_valid(hand_texture) and not is_snapping:
		hand_texture.position = current_bob + jitter

	# Terapkan ke tangan kiri jika tidak sedang animasi klik tombol
	if is_instance_valid(left_hand_texture) and not is_clicking:
		left_hand_texture.position = current_left_bob + jitter

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
	if exhausted:
		is_recovering_from_exhaustion = true
		target_blur_intensity = 1.0
	elif not is_recovering_from_exhaustion:
		target_blur_intensity = 0.0

func update_stamina_blur(stamina: float, max_stamina_val: float, exhausted: bool) -> void:
	is_exhausted = exhausted
	var stamina_ratio: float = clampf(stamina / max_stamina_val, 0.0, 1.0)

	if exhausted or stamina <= 0.0:
		is_recovering_from_exhaustion = true
		target_blur_intensity = 1.0
	elif is_recovering_from_exhaustion:
		target_blur_intensity = 1.0 - stamina_ratio
		if stamina_ratio >= 0.98:
			is_recovering_from_exhaustion = false
			target_blur_intensity = 0.0
	else:
		if stamina_ratio < 0.25:
			target_blur_intensity = (1.0 - (stamina_ratio / 0.25)) * 0.35
		else:
			target_blur_intensity = 0.0

func set_holding_breath(active: bool, stamina_ratio: float = 1.0) -> void:
	is_holding_breath = active
	hold_breath_stamina_ratio = stamina_ratio

func set_warning_zone(active: bool, intensity: float) -> void:
	fear_tremor_intensity = intensity if active else 0.0

func trigger_heartbeat_pulse() -> void:
	heartbeat_pulse = 1.0

func show_hold_breath_prompt() -> void:
	if not is_instance_valid(prompt_label) or prompt_is_visible:
		return
	prompt_is_visible = true
	if prompt_tween and prompt_tween.is_valid():
		prompt_tween.kill()
	prompt_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	prompt_tween.tween_property(prompt_label, "modulate:a", 0.9, 0.45)

func hide_hold_breath_prompt() -> void:
	if not is_instance_valid(prompt_label) or not prompt_is_visible:
		return
	prompt_is_visible = false
	if prompt_tween and prompt_tween.is_valid():
		prompt_tween.kill()
	prompt_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	prompt_tween.tween_property(prompt_label, "modulate:a", 0.0, 0.35)

func play_exhaustion_jolt() -> void:
	if jolt_tween and jolt_tween.is_valid():
		jolt_tween.kill()
	var jolt_dist: float = 38.0
	jolt_tween = create_tween()
	jolt_tween.set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_instance_valid(hand_texture):
		jolt_tween.tween_property(hand_texture, "position:y", current_bob.y + jolt_dist, 0.12)
	if is_instance_valid(left_hand_texture):
		jolt_tween.tween_property(left_hand_texture, "position:y", current_left_bob.y + jolt_dist, 0.12)
	jolt_tween.chain().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if is_instance_valid(hand_texture):
		jolt_tween.tween_property(hand_texture, "position:y", current_bob.y, 0.35)
	if is_instance_valid(left_hand_texture):
		jolt_tween.tween_property(left_hand_texture, "position:y", current_left_bob.y, 0.35)

func update_flashlight_heat(_heat: float, _max_heat_val: float, _is_on: bool, _overheated: bool) -> void:
	pass

func show_flashlight_ping_notice() -> void:
	pass

func update_flashlight_visual(is_on: bool) -> void:
	is_flashlight_lit = is_on
	_update_hand_modulate(0.0)

func play_overheat_warning(is_overheated_flag: bool) -> void:
	is_overheated_visual = is_overheated_flag
	_update_hand_modulate(0.0)

func _update_hand_modulate(delta: float = 0.0) -> void:
	var base_col: Color = COLOR_DIM
	if is_flashlight_lit:
		if is_overheated_visual:
			base_col = Color(0.72, 0.55, 0.55, 1.0)
		else:
			base_col = COLOR_LIT
	elif is_overheated_visual:
		base_col = Color(0.35, 0.22, 0.22, 1.0)

	base_col.a = 1.0
	if delta > 0.0:
		current_hand_color = current_hand_color.lerp(base_col, clampf(16.0 * delta, 0.0, 1.0))
	else:
		current_hand_color = base_col
	current_hand_color.a = 1.0

	if is_instance_valid(hand_texture):
		hand_texture.modulate = current_hand_color
	if is_instance_valid(left_hand_texture):
		left_hand_texture.modulate = current_hand_color

# ==============================================================================
# ALUR ANIMASI KLIK SENTER TANGAN KIRI (SPAM-CLICK RESPONSIVE TWEEN)
# ==============================================================================
func play_flashlight_click() -> void:
	if not is_instance_valid(left_hand_texture):
		return

	if click_tween and click_tween.is_valid():
		click_tween.kill()

	is_clicking = true

	if sprite_flashlight_click:
		left_hand_texture.texture = sprite_flashlight_click

	left_hand_texture.rotation = 0.0
	left_hand_texture.scale = Vector2.ONE

	var base_pos: Vector2 = current_left_bob
	var jolt_pos: Vector2 = base_pos + Vector2(-4.0, 15.0)

	click_tween = create_tween()
	click_tween.tween_property(left_hand_texture, "position", jolt_pos, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	click_tween.parallel().tween_property(left_hand_texture, "rotation", deg_to_rad(-3.5), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	click_tween.parallel().tween_property(left_hand_texture, "scale", Vector2(1.03, 0.96), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	click_tween.chain().tween_interval(0.09)

	click_tween.chain().tween_callback(func():
		if sprite_flashlight:
			left_hand_texture.texture = sprite_flashlight
	)

	click_tween.chain().tween_property(left_hand_texture, "position", base_pos, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	click_tween.parallel().tween_property(left_hand_texture, "rotation", 0.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	click_tween.parallel().tween_property(left_hand_texture, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	click_tween.chain().tween_callback(func():
		is_clicking = false
	)

func play_tap_recoil() -> void:
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

	if sprite_before_snap:
		hand_texture.texture = sprite_before_snap

	snap_tween = create_tween()
	snap_tween.tween_property(hand_texture, "position", Vector2(-12.0, -32.0), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "rotation", deg_to_rad(-6.0), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "scale", Vector2(0.97, 1.05), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	snap_tween.chain().tween_interval(0.04)

	snap_tween.chain().tween_callback(func():
		if sprite_after_snap:
			hand_texture.texture = sprite_after_snap
		if on_snap.is_valid():
			on_snap.call()
	)

	snap_tween.chain().tween_property(hand_texture, "position", Vector2(10.0, 22.0), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "rotation", deg_to_rad(7.0), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "scale", Vector2(1.08, 0.94), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	snap_tween.chain().tween_property(hand_texture, "position", Vector2.ZERO, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	snap_tween.parallel().tween_property(hand_texture, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	snap_tween.chain().tween_callback(func():
		if sprite_idle:
			hand_texture.texture = sprite_idle
		is_snapping = false
		current_bob = Vector2.ZERO
		if on_complete.is_valid():
			on_complete.call()
	)
