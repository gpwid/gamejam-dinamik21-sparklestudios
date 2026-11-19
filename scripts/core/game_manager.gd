extends Node

enum Difficulty {
	EASY,
	NORMAL,
	HARD,
	EXTREME
}

var current_difficulty: Difficulty = Difficulty.NORMAL

const RECORDS_PATH: String = "user://records.cfg"
var _config_file: ConfigFile = ConfigFile.new()
var best_times: Dictionary = {
	Difficulty.EASY: 0.0,
	Difficulty.NORMAL: 0.0,
	Difficulty.HARD: 0.0,
	Difficulty.EXTREME: 0.0
}

func get_difficulty_name() -> String:
	match current_difficulty:
		Difficulty.EASY: return "EASY"
		Difficulty.NORMAL: return "NORMAL"
		Difficulty.HARD: return "HARD"
		Difficulty.EXTREME: return "EXTREME"
	return "NORMAL"

func get_switches_count() -> int:
	match current_difficulty:
		Difficulty.EASY: return 3
		Difficulty.NORMAL: return 4
		Difficulty.HARD: return 5
		Difficulty.EXTREME: return 6
	return 4

func get_monster_patrol_speed() -> float:
	match current_difficulty:
		Difficulty.EASY: return 1.5
		Difficulty.NORMAL: return 1.8
		Difficulty.HARD: return 2.3
		Difficulty.EXTREME: return 2.8
	return 1.8

func get_monster_chase_speed() -> float:
	match current_difficulty:
		Difficulty.EASY: return 3.6
		Difficulty.NORMAL: return 4.2
		Difficulty.HARD: return 4.8
		Difficulty.EXTREME: return 5.5
	return 4.2

func get_monster_hearing_multiplier() -> float:
	match current_difficulty:
		Difficulty.EASY: return 0.75
		Difficulty.NORMAL: return 1.0
		Difficulty.HARD: return 1.33
		Difficulty.EXTREME: return 1.75
	return 1.0

func get_player_breath_drain_rate() -> float:
	match current_difficulty:
		Difficulty.EASY: return 5.0
		Difficulty.NORMAL: return 7.5
		Difficulty.HARD: return 12.0
		Difficulty.EXTREME: return 18.0
	return 7.5

func get_player_recovery_rate() -> float:
	match current_difficulty:
		Difficulty.EASY: return 24.0
		Difficulty.NORMAL: return 18.0
		Difficulty.HARD: return 13.5
		Difficulty.EXTREME: return 9.0
	return 18.0

const MENU_MUSIC: AudioStream = preload("res://assets/audio/music/menu_music.mp3")
const INGAME_1: AudioStream = preload("res://assets/audio/music/in-game_1.mp3")
const INGAME_2: AudioStream = preload("res://assets/audio/music/in_game_2.mp3")

enum MusicContext {
	NONE,
	MENU,
	INGAME
}

var music_player_a: AudioStreamPlayer
var music_player_b: AudioStreamPlayer
var active_player: AudioStreamPlayer
var active_tween: Tween

var current_context: MusicContext = MusicContext.NONE
var current_ingame_index: int = 0
var is_ducked: bool = false
var base_volume_db: float = -6.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_players()
	load_records()

func load_records() -> void:
	var err := _config_file.load(RECORDS_PATH)
	if err == OK:
		best_times[Difficulty.EASY] = float(_config_file.get_value("best_time", "easy", 0.0))
		best_times[Difficulty.NORMAL] = float(_config_file.get_value("best_time", "normal", 0.0))
		best_times[Difficulty.HARD] = float(_config_file.get_value("best_time", "hard", 0.0))
		best_times[Difficulty.EXTREME] = float(_config_file.get_value("best_time", "extreme", 0.0))

func get_best_time(diff: Difficulty) -> float:
	return float(best_times.get(diff, 0.0))

func format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--"
	var minutes := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%02d:%02d" % [minutes, secs]

func get_best_time_string(diff: Difficulty) -> String:
	return format_time(get_best_time(diff))

func save_best_time(diff: Difficulty, elapsed: float) -> bool:
	if elapsed <= 0.0:
		return false
	var current_best: float = get_best_time(diff)
	var is_new_record: bool = (current_best <= 0.0 or elapsed < current_best)
	if is_new_record:
		best_times[diff] = elapsed
		var key_name: String = _get_diff_key(diff)
		_config_file.set_value("best_time", key_name, elapsed)
		_config_file.save(RECORDS_PATH)
	return is_new_record

func _get_diff_key(diff: Difficulty) -> String:
	match diff:
		Difficulty.EASY: return "easy"
		Difficulty.NORMAL: return "normal"
		Difficulty.HARD: return "hard"
		Difficulty.EXTREME: return "extreme"
	return "normal"

func _setup_audio_players() -> void:
	music_player_a = AudioStreamPlayer.new()
	music_player_a.name = "MusicPlayerA"
	music_player_a.bus = &"Master"
	add_child(music_player_a)

	music_player_b = AudioStreamPlayer.new()
	music_player_b.name = "MusicPlayerB"
	music_player_b.bus = &"Master"
	add_child(music_player_b)

	active_player = music_player_a
	music_player_a.finished.connect(_on_music_finished)
	music_player_b.finished.connect(_on_music_finished)

func play_menu_music() -> void:
	if current_context == MusicContext.MENU and active_player and active_player.playing and not is_ducked:
		return
	current_context = MusicContext.MENU
	is_ducked = false
	_crossfade_to_stream(MENU_MUSIC, 1.2)

func play_ingame_music() -> void:
	if current_context == MusicContext.INGAME and active_player and active_player.playing:
		return
	current_context = MusicContext.INGAME
	is_ducked = false
	current_ingame_index = 0
	_crossfade_to_stream(INGAME_1, 2.0)

func set_ducked(duck: bool, speed: float = 0.5) -> void:
	if is_ducked == duck:
		return
	is_ducked = duck
	if active_player == null or not active_player.playing:
		return

	if active_tween and active_tween.is_valid():
		active_tween.kill()
	active_tween = create_tween()

	if is_ducked:
		active_tween.tween_property(active_player, "volume_db", -80.0, speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		active_tween.tween_property(active_player, "volume_db", base_volume_db, maxf(speed, 1.8)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func stop_music(fade_duration: float = 0.8) -> void:
	current_context = MusicContext.NONE
	is_ducked = false
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	if active_player and active_player.playing:
		active_tween = create_tween()
		active_tween.tween_property(active_player, "volume_db", -80.0, fade_duration)
		active_tween.tween_callback(func():
			if music_player_a: music_player_a.stop()
			if music_player_b: music_player_b.stop()
		)
	else:
		if music_player_a: music_player_a.stop()
		if music_player_b: music_player_b.stop()

func set_music_volume_percent(percent: float) -> void:
	if percent <= 0.0:
		base_volume_db = -80.0
	else:
		base_volume_db = -28.0 + (percent / 100.0) * 28.0
	if not is_ducked and active_player:
		active_player.volume_db = base_volume_db

func _crossfade_to_stream(stream: AudioStream, duration: float) -> void:
	if stream == null:
		return

	var outgoing := active_player
	var incoming := music_player_b if active_player == music_player_a else music_player_a
	active_player = incoming

	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()

	if active_tween and active_tween.is_valid():
		active_tween.kill()
	active_tween = create_tween().set_parallel(true)

	active_tween.tween_property(incoming, "volume_db", base_volume_db, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if outgoing and outgoing.playing:
		active_tween.tween_property(outgoing, "volume_db", -80.0, duration * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		active_tween.chain().tween_callback(outgoing.stop)

func _on_music_finished() -> void:
	if current_context == MusicContext.MENU:
		if active_player:
			active_player.play()
	elif current_context == MusicContext.INGAME:
		current_ingame_index = 1 if current_ingame_index == 0 else 0
		var next_stream: AudioStream = INGAME_2 if current_ingame_index == 1 else INGAME_1
		_crossfade_to_stream(next_stream, 3.0)
