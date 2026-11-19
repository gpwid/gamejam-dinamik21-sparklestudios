extends Control

@onready var video_player: VideoStreamPlayer = $VideoStreamPlayer
@onready var fade_rect: ColorRect = $FadeRect
@onready var skip_hint: Label = $SkipHint

var video_playlist: Array[String] = [
	"res://assets/ui/splash_screen.ogv",
	"res://assets/ui/headphone_message.ogv"
]
var current_video_index: int = 0
var is_transitioning: bool = false
var active_tween: Tween = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0, 1.0))

	if video_player:
		video_player.finished.connect(_on_video_finished)

	if fade_rect:
		fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
		fade_rect.modulate.a = 1.0

	_play_video(current_video_index)
	_fade_in(0.4)

func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or \
	   (event is InputEventMouseButton and event.pressed):
		_handle_skip()

func _handle_skip() -> void:
	if is_transitioning:
		return
	if current_video_index < video_playlist.size() - 1:
		_transition_to_video(current_video_index + 1)
	else:
		_transition_to_main_menu()

func _on_video_finished() -> void:
	if is_transitioning:
		return
	if current_video_index < video_playlist.size() - 1:
		_transition_to_video(current_video_index + 1)
	else:
		_transition_to_main_menu()

func _play_video(idx: int) -> void:
	if idx < video_playlist.size():
		var video_path := video_playlist[idx]
		if ResourceLoader.exists(video_path):
			var stream := load(video_path) as VideoStreamTheora
			video_player.stream = stream
			video_player.volume_db = 0.0
			video_player.play()
		else:
			_on_video_finished()
	else:
		_transition_to_main_menu()

func _fade_in(duration: float = 0.35) -> void:
	if not fade_rect:
		return
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	active_tween = create_tween()
	active_tween.tween_property(fade_rect, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _transition_to_video(next_idx: int) -> void:
	is_transitioning = true
	if active_tween and active_tween.is_valid():
		active_tween.kill()

	if fade_rect:
		fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)

	active_tween = create_tween()
	active_tween.set_parallel(true)
	if fade_rect:
		active_tween.tween_property(fade_rect, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if video_player:
		active_tween.tween_property(video_player, "volume_db", -40.0, 0.35)

	active_tween.chain().tween_callback(func():
		current_video_index = next_idx
		_play_video(current_video_index)
	)
	if fade_rect:
		active_tween.tween_property(fade_rect, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	active_tween.tween_callback(func():
		is_transitioning = false
	)

func _transition_to_main_menu() -> void:
	if is_transitioning:
		return
	is_transitioning = true

	if active_tween and active_tween.is_valid():
		active_tween.kill()

	active_tween = create_tween()
	active_tween.set_parallel(true)
	if fade_rect:
		fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
		active_tween.tween_property(fade_rect, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if video_player:
		active_tween.tween_property(video_player, "volume_db", -40.0, 0.45)

	active_tween.chain().tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	)
