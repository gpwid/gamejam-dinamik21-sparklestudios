extends Node

const MonsterScript = preload("res://scripts/characters/monster.gd")

func _ready() -> void:
	print("--- BEGIN TEST MONSTER MECHANICS ---")
	await test_patrol_initial_state()
	await test_patrol_active_movement_and_collision()
	await test_no_attack_in_patrol_or_investigate()
	await test_echolocation_reaction()
	await test_direct_shine_trigger()
	await test_overheat_trigger()
	await test_overheat_during_direct_shine_chase()
	await test_jumpscare_trigger()
	print("--- ALL MONSTER MECHANICS TESTS PASSED ---")
	get_tree().quit(0)

func test_patrol_initial_state() -> void:
	print("\n[Test 1] Patrol initial state")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var monster = monster_scene.instantiate()
	add_child(monster)
	await get_tree().process_frame

	monster.global_position = Vector3(0, 0, -5)

	assert(monster.current_state == MonsterScript.State.PATROL, "Monster should start in PATROL state")
	assert(monster.chase_source == MonsterScript.ChaseSource.NONE, "Chase source should be NONE")
	assert(monster.is_in_group("monster"), "Monster should be in 'monster' group")
	print("PASS: Monster starts in PATROL state")
	monster.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_patrol_active_movement_and_collision() -> void:
	print("\n[Test 1B] Patrol active movement and collision")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var monster = monster_scene.instantiate()
	add_child(monster)
	await get_tree().process_frame

	monster.global_position = Vector3(0, 0, 0)
	var wps: Array[Vector3] = [Vector3(5, 0, 0), Vector3(-5, 0, 0)]
	monster.patrol_waypoints = wps
	monster.current_waypoint_index = -1
	monster.target_position = monster.get_next_patrol_target()
	monster.is_waiting = false

	# 1. Periksa pergerakan aktif menuju target waypoint
	assert(monster.target_position == Vector3(5, 0, 0), "Target position should be first waypoint")
	monster._physics_process(0.1)
	assert(monster.velocity.x > 0.0, "Monster should move positively in X towards waypoint (5, 0, 0)")
	print("PASS: Monster moves actively towards waypoint")

	# 2. Periksa saat sampai di waypoint -> jeda diam 1.0 - 2.0 detik
	monster.global_position = Vector3(4.9, 0, 0)
	monster._physics_process(0.1)
	assert(monster.is_waiting == true, "Monster should enter waiting state when reaching waypoint")
	assert(monster.state_timer >= monster.patrol_wait_min and monster.state_timer <= monster.patrol_wait_max, "State timer should be within wait range")
	print("PASS: Monster pauses for 1.0-2.0s upon reaching waypoint")

	# 3. Jeda selesai -> memilih titik berikutnya
	monster.state_timer = 0.01
	monster._physics_process(0.02)
	assert(monster.is_waiting == false, "Monster should resume after wait timer finishes")
	assert(is_equal_approx(monster.target_position.x, -5.0) and is_equal_approx(monster.target_position.z, 0.0), "Monster should pick next waypoint")
	print("PASS: Monster picks next target after pause")

	# 4. Deteksi stuck tabrakan (> 1.0s) -> ganti target
	var prev_target = monster.target_position
	# Simulasi stuck timer mencapai batas wall_stuck_timeout
	monster.stuck_timer = monster.wall_stuck_timeout
	# Buat kondisi horiz_vel > 0.4 dan real_speed < 0.12 atau panggil langsung
	monster.velocity = Vector3(1.5, 0, 0)
	# Jalankan update saat stuck_timer sudah mencapai batas
	monster._update_patrol(0.05)
	assert(monster.stuck_timer == 0.0, "Stuck timer should reset after picking new target")
	assert(monster.target_position != prev_target, "Monster should pick a new patrol target when stuck")
	print("PASS: Monster recovers and changes patrol target after being stuck")

	monster.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_no_attack_in_patrol_or_investigate() -> void:
	print("\n[Test 1C] No attack in Patrol or Investigate")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()

	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3(0, 0, 0)
	monster.global_position = Vector3(0, 0, 0.5) # Sangat dekat, di dalam jumpscare_distance (1.4m)
	player.is_flashlight_on = false # Senter mati agar tidak memicu direct shine

	# Dalam status PATROL
	monster.current_state = MonsterScript.State.PATROL
	monster._physics_process(0.1)
	assert(monster.current_state == MonsterScript.State.PATROL, "Monster must remain in PATROL when player is nearby")
	assert(player.is_jumpscared == false, "Player must NOT be jumpscared in PATROL")
	print("PASS: No attack/jumpscare while in PATROL even when close to player")

	# Dalam status INVESTIGATE
	monster.current_state = MonsterScript.State.INVESTIGATE
	monster._physics_process(0.1)
	assert(monster.current_state == MonsterScript.State.INVESTIGATE, "Monster must remain in INVESTIGATE when player is nearby")
	assert(player.is_jumpscared == false, "Player must NOT be jumpscared in INVESTIGATE")
	print("PASS: No attack/jumpscare while in INVESTIGATE even when close to player")

	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_echolocation_reaction() -> void:
	print("\n[Test 2] Echolocation reaction (Hear & Approach, No Attack)")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()

	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3(0, 0, 0)
	monster.global_position = Vector3(0, 0, 4.0)

	# Trigger echolocation within 6.0m
	var tap_pos = Vector3(0, 0, 1.0)
	player.echolocation_made.emit(tap_pos, player.floor_tap_max_radius)

	assert(monster.current_state == MonsterScript.State.INVESTIGATE, "Monster should transition to INVESTIGATE")
	assert(monster.target_position == tap_pos, "Monster target position should be sound origin")
	assert(monster.chase_source == MonsterScript.ChaseSource.NONE, "Monster must NOT enter chase on sound")
	print("PASS: Monster heard echolocation within 6m and investigated without attacking")

	# Test outside hearing radius (e.g. 15m away)
	monster._enter_patrol()
	player.global_position = Vector3(0, 0, 20.0)
	player.echolocation_made.emit(Vector3(0, 0, 20.0), player.floor_tap_max_radius)
	assert(monster.current_state == MonsterScript.State.PATROL, "Monster should ignore sound outside hearing radius")
	print("PASS: Monster ignored sound beyond hearing radius")

	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_direct_shine_trigger() -> void:
	print("\n[Test 3] Direct Shine Trigger (Kondisi B)")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()

	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3(0, 0, 0)
	monster.global_position = Vector3(0, 0, -6.0)

	player.head.rotation = Vector3.ZERO
	player.rotation = Vector3.ZERO

	player.is_flashlight_on = true
	player.flashlight.visible = true
	player.flashlight.light_energy = 1.0
	player.flashlight.spot_range = 25.0
	player.flashlight.spot_angle = 45.0

	await get_tree().physics_frame

	var is_lit = monster.check_direct_flashlight_shine()
	assert(is_lit == true, "Monster should be detected in direct flashlight beam")

	monster.trigger_direct_shine_chase()
	assert(monster.current_state == MonsterScript.State.CHASE, "Monster should be in CHASE")
	assert(monster.chase_source == MonsterScript.ChaseSource.DIRECT_SHINE, "Chase source should be DIRECT_SHINE")
	assert(player.is_triggered == false, "Player flashlight MUST remain normal (is_triggered == false) on Kondisi B")
	print("PASS: Direct shine triggered CHASE while player flashlight stayed normal")

	# Pemain mematikan senter / sembunyi (evade)
	player.is_flashlight_on = false
	player.flashlight.visible = false
	player.flashlight.light_energy = 0.0

	# Test timeout back to patrol
	monster.direct_chase_timer = 0.05
	monster._physics_process(0.1)
	assert(monster.current_state == MonsterScript.State.PATROL, "Monster should return to PATROL after direct chase timeout")
	print("PASS: Monster returned to PATROL after evading direct shine chase")

	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_overheat_trigger() -> void:
	print("\n[Test 4] Overheat Trigger (Kondisi A)")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()

	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3(0, 0, 0)
	monster.global_position = Vector3(0, 0, -10.0)

	# Trigger player overheat
	player._trigger_overheat()
	assert(player.is_triggered == true, "Player flashlight should be triggered/overheated")

	assert(monster.current_state == MonsterScript.State.CHASE, "Monster should enter CHASE on overheat")
	assert(monster.chase_source == MonsterScript.ChaseSource.OVERHEAT, "Chase source should be OVERHEAT")
	print("PASS: Flashlight overheat (100% exposure) triggered monster CHASE")

	# When player cools down to 0%, monster returns to patrol
	player.is_triggered = false
	player.current_exposure = 0.0
	monster._physics_process(0.1)
	assert(monster.current_state == MonsterScript.State.PATROL, "Monster should return to PATROL when overheat ends")
	print("PASS: Monster returned to PATROL when overheat cooldown finished")

	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_overheat_during_direct_shine_chase() -> void:
	print("\n[Test 4B] Overheat during Direct Shine Chase (No Double Trigger / Reset)")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()

	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3(0, 0, 0)
	monster.global_position = Vector3(0, 0, -6.0)

	# Trigger direct shine chase first
	monster.trigger_direct_shine_chase()
	assert(monster.current_state == MonsterScript.State.CHASE)
	assert(monster.chase_source == MonsterScript.ChaseSource.DIRECT_SHINE)

	# Player exposure reaches 100% while being chased
	player._trigger_overheat()
	assert(player.is_triggered == true, "Player flashlight overheated")
	assert(monster.current_state == MonsterScript.State.CHASE, "Monster must remain in CHASE")
	assert(monster.chase_source == MonsterScript.ChaseSource.OVERHEAT, "Chase source gracefully upgraded to OVERHEAT")
	print("PASS: Overheat during direct shine chase handled without double trigger or chase interruption")

	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_jumpscare_trigger() -> void:
	print("\n[Test 5] Jumpscare & Game Over Trigger")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()

	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3(0, 0, 0)
	monster.global_position = Vector3(0, 0, -1.0) # Within jumpscare_distance (1.4m)
	monster.current_state = MonsterScript.State.CHASE
	monster.chase_source = MonsterScript.ChaseSource.DIRECT_SHINE

	monster._physics_process(0.016)
	assert(monster.current_state == MonsterScript.State.JUMPSCARE, "Monster should transition to JUMPSCARE")
	assert(player.is_jumpscared == true, "Player should be locked in jumpscare")

	# Wait for jumpscare delay to show game over UI
	monster.state_timer = 0.05
	monster._physics_process(0.1)
	assert(monster.game_over_ui.visible == true, "Game Over UI should become visible")
	assert(monster.game_over_ui.is_active == true, "Game Over UI should be active")
	print("PASS: Jumpscare triggered lock, camera focus, and Game Over UI")

	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
