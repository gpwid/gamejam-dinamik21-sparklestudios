extends CanvasLayer
class_name VictoryUI

@onready var white_overlay: ColorRect = $WhiteOverlay
@onready var content_container: Control = $ContentContainer
@onready var title_label: Label = $ContentContainer/CenterContainer/VBoxContainer/TitleLabel
@onready var subtitle_label: Label = $ContentContainer/CenterContainer/VBoxContainer/SubtitleLabel
@onready var time_label: Label = $ContentContainer/CenterContainer/VBoxContainer/StatsBox/TimeLabel
@onready var switches_label: Label = $ContentContainer/CenterContainer/VBoxContainer/StatsBox/SwitchesLabel
@onready var retry_button: Button = $ContentContainer/CenterContainer/VBoxContainer/ButtonBox/RetryButton
@onready var menu_button: Button = $ContentContainer/CenterContainer/VBoxContainer/ButtonBox/MenuButton

@export var click_sound: AudioStream = preload("res://assets/audio/sfx/switch.wav")
var is_active: bool = false

func _ready() -> void:
	visible = false
	white_overlay.modulate.a = 0.0
	content_container.modulate.a = 0.0
	
	if retry_button:
		retry_button.pressed.connect(_on_retry_pressed)
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)

func show_victory(elapsed_seconds: float, switches_count: int, total_switches: int) -> void:
	if is_active:
		return
	is_active = true
	visible = true
	
	# Format waktu MM:SS
	var minutes := int(elapsed_seconds) / 60
	var seconds := int(elapsed_seconds) % 60
	var time_str := "%02d:%02d" % [minutes, seconds]
	
	if time_label:
		time_label.text = "WAKTU KABUR : " + time_str
	if switches_label:
		switches_label.text = "SAKLAR DIAKTIFKAN : %d / %d" % [switches_count, total_switches]
	
	# Fade-to-White menyilaukan
	var tween := create_tween()
	tween.tween_property(white_overlay, "modulate:a", 1.0, 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.4)
	# Fade-in konten teks & tombol di atas layar putih
	tween.tween_property(content_container, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if retry_button:
			retry_button.grab_focus()
	)

func _play_click_sfx() -> void:
	if click_sound:
		var sfx := AudioStreamPlayer.new()
		sfx.stream = click_sound
		sfx.pitch_scale = 1.1
		add_child(sfx)
		sfx.play()

func _on_retry_pressed() -> void:
	_play_click_sfx()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if is_inside_tree() and get_tree():
		var monsters := get_tree().get_nodes_in_group("monster")
		for m in monsters:
			if m.has_method("reset_monster_visuals"):
				m.reset_monster_visuals()
		get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	_play_click_sfx()
	if is_inside_tree() and get_tree():
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
