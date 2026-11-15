extends CanvasLayer
class_name GameOverUI

@onready var root_control: Control = $RootControl
@onready var color_rect: ColorRect = $RootControl/ColorRect
@onready var container: Control = $RootControl/CenterContainer
@onready var title_label: Label = $RootControl/CenterContainer/VBoxContainer/TitleLabel
@onready var retry_button: Button = $RootControl/CenterContainer/VBoxContainer/RetryButton

var is_active: bool = false

func _ready() -> void:
	visible = false
	if retry_button:
		retry_button.pressed.connect(_on_retry_pressed)

func show_game_over() -> void:
	if is_active:
		return
	is_active = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if root_control:
		root_control.modulate.a = 0.0
		var tween := create_tween()
		if tween:
			tween.tween_property(root_control, "modulate:a", 1.0, 0.35)
		else:
			root_control.modulate.a = 1.0

	if retry_button:
		retry_button.grab_focus()

func _on_retry_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if is_inside_tree() and get_tree():
		var monsters := get_tree().get_nodes_in_group("monster")
		for m in monsters:
			if m.has_method("reset_monster_visuals"):
				m.reset_monster_visuals()
		get_tree().reload_current_scene()
