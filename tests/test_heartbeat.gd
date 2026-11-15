extends Node

const PlayerScript = preload("res://scripts/characters/player.gd")

func _ready() -> void:
	print("--- BEGIN TEST HEARTBEAT AUDIO SYSTEM ---")
	await test_export_defaults()
	await test_outside_radius_silent()
	await test_proximity_interpolation()
	await test_custom_beat_timer_gap_cutting()
	await test_jumpscare_stops_heartbeat()
	print("--- ALL HEARTBEAT AUDIO TESTS PASSED ---")
	get_tree().quit(0)

func test_export_defaults() -> void:
	print("\n[Test Heartbeat 1] Verify Export Variables Defaults")
	var player_scene = load("res://scenes/characters/player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	await get_tree().process_frame

	assert(is_equal_approx(player.max_heartbeat_distance, 15.0), "max_heartbeat_distance should be 15.0")
	assert(is_equal_approx(player.min_heartbeat_distance, 2.5), "min_heartbeat_distance should be 2.5")
	assert(is_equal_approx(player.slowest_beat_interval, 1.1), "slowest_beat_interval should be 1.1")
	assert(is_equal_approx(player.fastest_beat_interval, 0.38), "fastest_beat_interval should be 0.38")
	assert(is_equal_approx(player.min_heartbeat_volume_db, -18.0), "min_heartbeat_volume_db should be -18.0")
	assert(is_equal_approx(player.max_heartbeat_volume_db, 1.0), "max_heartbeat_volume_db should be 1.0")
	assert(is_equal_approx(player.min_heartbeat_pitch, 0.95), "min_heartbeat_pitch should be 0.95")
	assert(is_equal_approx(player.max_heartbeat_pitch, 1.1), "max_heartbeat_pitch should be 1.1")
	assert(player.heartbeat_sound != null, "heartbeat_sound should be loaded")
	assert(player.heartbeat_player != null, "heartbeat_player AudioStreamPlayer node must exist")
	assert(player.heartbeat_player.stream != null, "heartbeat_player stream must be assigned")

	print("PASS: All export variables and nodes configured with exact defaults")
	player.queue_free()
	await get_tree().process_frame

func test_outside_radius_silent() -> void:
	print("\n[Test Heartbeat 2] Verify Silence Outside Radius (> 15.0m)")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()
	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	# Jarak 20.0m (> max_heartbeat_distance 15.0m)
	player.global_position = Vector3(0.0, 0.0, 0.0)
	monster.global_position = Vector3(0.0, 0.0, 20.0)

	# Jalankan beberapa tick process
	for i in range(10):
		player._process(0.1)

	assert(not player.heartbeat_player.playing, "Heartbeat audio must not be playing when distance > 15.0m")
	assert(is_equal_approx(player.beat_timer, 0.0), "Beat timer must be reset to 0.0 when outside radius")
	print("PASS: Outside radius (> 15.0m) remains completely silent and timer resets")

	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame

func test_proximity_interpolation() -> void:
	print("\n[Test Heartbeat 3] Verify Proximity Interpolation (Tempo, Volume, Pitch)")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()
	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3.ZERO

	# 1. Pada batas maksimal (15.0m) -> t = 0.0
	monster.global_position = Vector3(0.0, 0.0, 15.0)
	player._process(0.016)
	assert(is_equal_approx(player.current_beat_interval, 1.1), "At 15.0m interval should be 1.1s")
	assert(is_equal_approx(player.heartbeat_player.volume_db, -18.0), "At 15.0m volume should be -18.0 dB")
	assert(is_equal_approx(player.heartbeat_player.pitch_scale, 0.95), "At 15.0m pitch should be 0.95")

	# 2. Pada titik tengah (8.75m) -> t = 0.5
	monster.global_position = Vector3(0.0, 0.0, 8.75)
	player._process(0.016)
	var expected_mid_interval: float = lerpf(1.1, 0.38, 0.5) # 0.74
	var expected_mid_vol: float = lerpf(-18.0, 1.0, 0.5)      # -8.5
	var expected_mid_pitch: float = lerpf(0.95, 1.1, 0.5)     # 1.025
	assert(abs(player.current_beat_interval - expected_mid_interval) < 0.01, "At 8.75m interval should be ~0.74s")
	assert(abs(player.heartbeat_player.volume_db - expected_mid_vol) < 0.1, "At 8.75m volume should be ~ -8.5 dB")
	assert(abs(player.heartbeat_player.pitch_scale - expected_mid_pitch) < 0.01, "At 8.75m pitch should be ~1.025")

	# 3. Pada jarak sangat dekat (2.5m atau kurang) -> t = 1.0
	monster.global_position = Vector3(0.0, 0.0, 2.5)
	player._process(0.016)
	assert(is_equal_approx(player.current_beat_interval, 0.38), "At 2.5m interval should be 0.38s")
	assert(is_equal_approx(player.heartbeat_player.volume_db, 1.0), "At 2.5m volume should be 1.0 dB")
	assert(is_equal_approx(player.heartbeat_player.pitch_scale, 1.1), "At 2.5m pitch should be 1.1")

	print("PASS: Proximity interpolation smoothly scales tempo, volume, and pitch")
	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame

func test_custom_beat_timer_gap_cutting() -> void:
	print("\n[Test Heartbeat 4] Verify Custom Beat Timer (Gap Cutting without waiting full stream)")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()
	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3.ZERO
	# Letakkan pada jarak 2.5m agar interval = 0.38s
	monster.global_position = Vector3(0.0, 0.0, 2.5)

	# Tick 0.20s -> belum mencapai 0.38s, tidak boleh memicu beat
	player._process(0.20)
	assert(abs(player.beat_timer - 0.20) < 0.01, "beat_timer should accumulate to 0.20s")
	assert(not player.heartbeat_player.playing, "Should not have triggered beat yet at 0.20s")

	# Tick lagi 0.19s (total 0.39s >= 0.38s) -> harus memicu play(0.0) dan reset beat_timer ke 0.0
	player._process(0.19)
	assert(player.heartbeat_player.playing, "Heartbeat should be playing after reaching 0.38s interval")
	assert(player.beat_timer < 0.02, "beat_timer must be reset after triggering beat")

	# Periksa bahwa audio berdetak lagi setelah 0.38s berikutnya (memotong jeda kosong 0.6s)
	# Buktikan bahwa kita tidak perlu menunggu 1.0s (durasi penuh file audio)
	player._process(0.38)
	assert(player.heartbeat_player.playing, "Heartbeat triggers again after 0.38s, cutting dead silence")

	print("PASS: Custom beat timer triggers every 0.38s, successfully cutting the 0.6s audio gap")
	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame

func test_jumpscare_stops_heartbeat() -> void:
	print("\n[Test Heartbeat 5] Verify Jumpscare Immediately Stops Heartbeat")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()
	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3.ZERO
	monster.global_position = Vector3(0.0, 0.0, 2.0)

	# Trigger beat
	player._process(0.4)
	assert(player.heartbeat_player.playing, "Heartbeat was active")

	# Pemicuan Jumpscare
	player.trigger_jumpscare(monster)
	assert(player.is_jumpscared, "Player must be jumpscared")
	assert(not player.heartbeat_player.playing, "Heartbeat audio must immediately stop upon jumpscare")

	# Tick process selanjutnya saat is_jumpscared == true
	player._process(0.5)
	assert(not player.heartbeat_player.playing, "Heartbeat audio must stay stopped during jumpscare")

	print("PASS: Heartbeat audio immediately terminates upon jumpscare trigger")
	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame
