extends CanvasLayer
class_name ViewModel

@onready var hand_texture: TextureRect = $HandContainer/HandTexture

var recoil_tween: Tween

const COLOR_LIT: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_DIM: Color = Color(0.25, 0.25, 0.3, 1.0)
const COLOR_OVERHEAT: Color = Color(0.9, 0.2, 0.2, 1.0)
const BREATH_FREQUENCY: float = 1.6
const BREATH_AMPLITUDE_PX: float = 4.0
const BREATH_LERP_SPEED: float = 8.0

var is_idle: bool = false
var breath_time: float = 0.0

func _ready() -> void:
	if not hand_texture or hand_texture.texture == null:
		push_warning("ViewModel: Placeholder texture not assigned or missing at res://assets/textures/placeholders/fpp_hand_placeholder.png")
	update_flashlight_visual(false)

func _process(delta: float) -> void:
	if not is_instance_valid(hand_texture):
		return
	if recoil_tween and recoil_tween.is_valid():
		return

	var target_y: float = 0.0
	if is_idle:
		breath_time += BREATH_FREQUENCY * delta
		# Tetap di [0..BREATH_AMPLITUDE_PX] agar pangkal lengan tidak terangkat dari tepi bawah layar
		target_y = (1.0 - cos(breath_time)) * 0.5 * BREATH_AMPLITUDE_PX
	else:
		breath_time = 0.0

	hand_texture.position.y = lerpf(hand_texture.position.y, target_y, minf(BREATH_LERP_SPEED * delta, 1.0))

func set_idle(idle: bool) -> void:
	is_idle = idle

func update_flashlight_visual(is_on: bool) -> void:
	if not is_instance_valid(hand_texture):
		return
	var target_col: Color = COLOR_LIT if is_on else COLOR_DIM
	if hand_texture.modulate != target_col:
		hand_texture.modulate = target_col

func play_overheat_warning(is_overheated: bool) -> void:
	if not is_instance_valid(hand_texture):
		return
	if is_overheated:
		hand_texture.modulate = COLOR_OVERHEAT
	else:
		update_flashlight_visual(false)

func play_tap_recoil() -> void:
	if not is_instance_valid(hand_texture):
		return
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()
		
	# Hentakan tangan saat mengetuk dinding (turun 25px lalu memantul kembali)
	recoil_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	recoil_tween.tween_property(hand_texture, "position:y", 25.0, 0.08)
	recoil_tween.tween_property(hand_texture, "position:y", 0.0, 0.16)
