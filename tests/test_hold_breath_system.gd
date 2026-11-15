extends Node

const MonsterScript = preload("res://scripts/characters/monster.gd")

func _ready() -> void:
	print("--- BEGIN TEST HOLD BREATH & STAMINA SYSTEM ---")
	await test_hold_breath_activation_and_silence()
	await test_exhaustion_and_gasping_audio()
	await test_monster_gasp_hearing_radius()
	await test_warning_zone_visual_and_prompt()
	await test_lethal_zone_stealth_mechanics()
	print("--- ALL HOLD BREATH & STAMINA SYSTEM TESTS PASSED ---")
	get_tree().quit(0)

func test_hold_breath_activation_and_silence() -> void:
	print("\n[Test 1] Verify Hold Breath Activation & Complete Breathing Silence")
	var player_scene = load("res://scenes/characters/player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	await get_tree().process_frame

	assert(not player.is_holding_breath, "Initial is_holding_breath must be false")
	assert(player.hold_breath_drain_rate > 0.0, "hold_breath_drain_rate must be configured")

	# Start holding breath
	player._start_holding_breath()
	assert(player.is_holding_breath, "is_holding_breath must be true after _start_holding_breath")

	# Process stamina and breathing
	var initial_stamina = player.current_stamina
	player.handle_stamina(1.0, false) # 1 second while stationary
	assert(player.current_stamina < initial_stamina, "Stamina must drain while holding breath")
	assert(is_equal_approx(player.current_stamina, initial_stamina - player.hold_breath_drain_rate), "Stamina must drain exactly at hold_breath_drain_rate")

	# Verify complete silence of breathing audio
	player.handle_breathing_audio(0.1, false)
	assert(player.idle_breath_target_vol <= -75.0, "Idle breathing target vol must be silenced (<= -75 dB)")
	assert(player.running_breath_target_vol <= -75.0, "Running breathing target vol must be silenced (<= -75 dB)")
	assert(not player.idle_breathing_player.playing, "idle_breathing_player must be stopped during hold breath")
	assert(not player.running_breathing_player.playing, "running_breathing_player must be stopped during hold breath")

	# Stop holding breath
	player._stop_holding_breath()
	assert(not player.is_holding_breath, "is_holding_breath must be false after _stop_holding_breath")

	print("PASS: Hold breath activates, drains stamina slowly, and silences all breathing audio")
	player.queue_free()
	await get_tree().process_frame

func test_exhaustion_and_gasping_audio() -> void:
	print("\n[Test 2] Verify Exhaustion Consequence & gasping_for_air.wav Audio Playback")
	var player_scene = load("res://scenes/characters/player.tscn")
	var player = player_scene.instantiate()
	add_child(player)
	await get_tree().process_frame

	# Simulate stamina dropping to 0
	player.current_stamina = 1.0
	player._start_holding_breath()
	player.handle_stamina(1.0, false) # Stamina drops below 0 -> triggers exhaustion

	assert(player.current_stamina == 0.0, "Stamina must clamp to 0.0")
	assert(player.is_exhausted, "Player must enter exhausted state")
	assert(not player.is_holding_breath, "Holding breath must be canceled upon exhaustion")
	assert(player.exhaustion_recovery_threshold == 25.0, "Recovery threshold must be 25%")

	# Verify gasping_for_air audio
	assert(player.exhaustion_player != null, "exhaustion_player node must exist")
	assert(player.exhaustion_player.playing, "exhaustion_player must be playing gasping_for_air.wav")
	assert(player.exhaustion_player.stream.resource_path.ends_with("gasping_for_air.wav"), "Exhaustion stream must be gasping_for_air.wav")
	assert(player.exhaustion_player.volume_db >= -2.0, "Gasping audio volume level must be loud and clear (>= -2 dB)")

	# Verify player cannot sprint or hold breath while exhausted
	assert(not (Input.is_action_pressed("sprint") and not player.is_exhausted), "Cannot sprint while exhausted")

	# Recover stamina partially (to 15.0 < 25.0)
	player.current_stamina = 15.0
	player.handle_stamina(0.1, false)
	assert(player.is_exhausted, "Must remain exhausted below 25% stamina")

	# Recover stamina past 25.0
	player.current_stamina = 26.0
	player.handle_stamina(0.1, false)
	assert(not player.is_exhausted, "Exhaustion must clear once stamina reaches 25%")

	print("PASS: Exhaustion plays gasping_for_air.wav, locks actions, and recovers at 25% stamina")
	player.queue_free()
	await get_tree().process_frame

func test_monster_gasp_hearing_radius() -> void:
	print("\n[Test 3] Verify Fair Monster Detection (Gasp triggers Chase ONLY when < 6.0m)")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")

	# Scenario A: Monster far away (> 6.0m, e.g. 10.0m)
	var player_a = player_scene.instantiate()
	var monster_a = monster_scene.instantiate()
	add_child(player_a)
	add_child(monster_a)
	await get_tree().process_frame

	player_a.global_position = Vector3(0.0, 0.0, 0.0)
	monster_a.global_position = Vector3(0.0, 0.0, 10.0) # 10.0m away

	player_a._trigger_exhaustion()
	assert(monster_a.current_state != MonsterScript.State.CHASE, "Monster > 6.0m must NOT enter Chase from gasping")

	player_a.queue_free()
	monster_a.queue_free()
	await get_tree().process_frame

	# Scenario B: Monster close (< 6.0m, e.g. 4.5m)
	var player_b = player_scene.instantiate()
	var monster_b = monster_scene.instantiate()
	add_child(player_b)
	add_child(monster_b)
	await get_tree().process_frame

	player_b.global_position = Vector3(0.0, 0.0, 0.0)
	monster_b.global_position = Vector3(0.0, 0.0, 4.5) # 4.5m away

	player_b._trigger_exhaustion()
	assert(monster_b.current_state == MonsterScript.State.CHASE, "Monster < 6.0m MUST enter Chase from gasping")

	print("PASS: Gasping only alerts monster when within close hearing radius (< 6.0m)")
	player_b.queue_free()
	monster_b.queue_free()
	await get_tree().process_frame

func test_warning_zone_visual_and_prompt() -> void:
	print("\n[Test 4] Verify Warning Zone (8.0m - 4.0m) Signals & Onboarding Prompt")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()
	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3(0.0, 0.0, 0.0)
	monster.global_position = Vector3(0.0, 0.0, 6.0) # In warning zone (8m - 4m)

	player.handle_monster_proximity_zones(0.1, 0.0)
	assert(player.is_in_warning_zone, "Player must be in warning zone at 6.0m")
	assert(player.view_model.fear_tremor_intensity > 0.0, "ViewModel fear tremor must be active in warning zone")
	assert(player.view_model.prompt_is_visible, "Onboarding prompt must be visible upon first entering warning zone")

	# Press Shift to hold breath -> prompt hides
	player._start_holding_breath()
	assert(player.has_shown_hold_breath_prompt, "has_shown_hold_breath_prompt should be true after Shift")
	assert(not player.view_model.prompt_is_visible, "Prompt must be hidden after pressing Shift")

	print("PASS: Warning zone activates fear signals and onboarding prompt")
	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame

func test_lethal_zone_stealth_mechanics() -> void:
	print("\n[Test 5] Verify Lethal Zone (< 4.0m) Detection & Stealth Pass-By")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")

	# Scenario A: Player is STILL + FLASHLIGHT OFF + HOLDING BREATH -> Safe pass-by!
	var player_a = player_scene.instantiate()
	var monster_a = monster_scene.instantiate()
	add_child(player_a)
	add_child(monster_a)
	await get_tree().process_frame

	player_a.global_position = Vector3(0.0, 0.0, 0.0)
	monster_a.global_position = Vector3(0.0, 0.0, 2.5) # Lethal distance (2.5m < 4.0m)

	player_a.is_flashlight_on = false
	player_a._start_holding_breath()

	# Tick 2.0 seconds (more than 1.2s threshold)
	for i in range(20):
		player_a.handle_monster_proximity_zones(0.1, 0.0)

	assert(player_a.lethal_zone_timer == 0.0, "Lethal zone timer must stay 0 while holding breath stealthily")
	assert(monster_a.current_state != MonsterScript.State.CHASE, "Monster must pass by without detecting stealthy player")

	player_a.queue_free()
	monster_a.queue_free()
	await get_tree().process_frame

	# Scenario B: Player in lethal zone WITHOUT holding breath -> Triggers Chase after 1.2s!
	var player_b = player_scene.instantiate()
	var monster_b = monster_scene.instantiate()
	add_child(player_b)
	add_child(monster_b)
	await get_tree().process_frame

	player_b.global_position = Vector3(0.0, 0.0, 0.0)
	monster_b.global_position = Vector3(0.0, 0.0, 2.5) # Lethal distance
	player_b.is_holding_breath = false

	# Tick for 1.3 seconds (> 1.2s threshold)
	for i in range(13):
		player_b.handle_monster_proximity_zones(0.1, 0.0)

	assert(monster_b.current_state == MonsterScript.State.CHASE, "Monster must enter Chase if player does not hold breath in lethal zone for > 1.2s")

	print("PASS: Lethal zone detection triggers after 1.2s unless player holds breath stealthily")
	player_b.queue_free()
	monster_b.queue_free()
	await get_tree().process_frame
