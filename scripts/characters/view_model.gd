extends CanvasLayer
class_name ViewModel

@onready var hand_texture: TextureRect = $HandContainer/HandTexture

var recoil_tween: Tween

const COLOR_LIT: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_DIM: Color = Color(0.25, 0.25, 0.3, 1.0)
const COLOR_OVERHEAT: Color = Color(0.9, 0.2, 0.2, 1.0)

func _ready() -> void:
	if not hand_texture or hand_texture.texture == null:
		push_warning("ViewModel: Placeholder texture not assigned or missing at res://assets/textures/placeholders/fpp_hand_placeholder.png")
	update_flashlight_visual(false)

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
