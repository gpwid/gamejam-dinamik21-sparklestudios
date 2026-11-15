extends Node

const MonsterScript = preload("res://scripts/characters/monster.gd")

func _ready() -> void:
	print("--- BEGIN TEST MONSTER NAVIGATION (A* & RAYCAST SMOOTHING) ---")
	await test_chase_duration_4s()
	await test_world_autoscan_obstacles()
	await test_shortest_path_around_obstacles()
	await test_echolocation_investigate_path()
	await test_chase_pathfinding_and_smoothing()
	print("--- ALL MONSTER NAVIGATION TESTS PASSED ---")
	get_tree().quit(0)

func test_chase_duration_4s() -> void:
	print("\n[Test Nav 1] Verify Direct Shine Chase Duration is 4.0 Seconds")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()
	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3(0, 0, 15.0) # Far away, no jumpscare
	assert(is_equal_approx(monster.direct_trigger_chase_duration, 4.0), "direct_trigger_chase_duration must be 4.0s")
	monster.trigger_direct_shine_chase()
	assert(is_equal_approx(monster.direct_chase_timer, 4.0), "direct_chase_timer must be initialized to 4.0s")
	assert(monster.current_state == MonsterScript.State.CHASE, "Monster must be in CHASE state")

	# Senter mati/tidak menyorot terus -> hitung mundur timer
	player.is_flashlight_on = false

	# Simulate 3.9 seconds elapsed without direct shine -> still chasing
	monster._physics_process(3.9)
	assert(monster.current_state == MonsterScript.State.CHASE, "Monster should still be in CHASE after 3.9s")

	# Simulate another 0.2 seconds elapsed (total 4.1s) -> returns to PATROL
	monster._physics_process(0.2)
	assert(monster.current_state == MonsterScript.State.PATROL, "Monster must return to PATROL after 4.0s timeout")
	print("PASS: Direct shine chase duration is exactly 4.0s and smoothly returns to PATROL")

	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame

func test_world_autoscan_obstacles() -> void:
	print("\n[Test Nav 2] Verify Auto-Scan AStarGrid2D in test_world.tscn")
	var world_scene = load("res://scenes/level/test_world.tscn")
	var world = world_scene.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame

	var monster = world.get_node("Monster")
	assert(monster != null, "Monster should exist in test_world.tscn")
	assert(monster.astar_grid != null, "astar_grid should be initialized")

	var grid: AStarGrid2D = monster.astar_grid
	var r := grid.region
	assert(r.size.x > 0 and r.size.y > 0, "Grid size should be valid")

	# Table is around (0.48, -2.67). Check that cells around table are marked solid
	var table_cell = monster.world_to_grid(Vector3(0.48, 0.0, -2.67))
	assert(grid.is_point_solid(table_cell), "Table location must be detected as solid obstacle")

	# Check back wall at Z = -9.4 is solid
	var wall_cell = monster.world_to_grid(Vector3(0.0, 0.0, -9.4))
	assert(grid.is_point_solid(wall_cell), "Back wall must be detected as solid obstacle")

	# Check open area at (0, 0, 2.0) is walkable
	var open_cell = monster.world_to_grid(Vector3(0.0, 0.0, 2.0))
	assert(not grid.is_point_solid(open_cell), "Open center area must be walkable (not solid)")

	print("PASS: Auto-Scan successfully identified static bodies and CSGBox3D obstacles")
	world.queue_free()
	await get_tree().process_frame

func test_shortest_path_around_obstacles() -> void:
	print("\n[Test Nav 3] Shortest Path calculation around Table / Obstacle")
	var world_scene = load("res://scenes/level/test_world.tscn")
	var world = world_scene.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame

	var monster = world.get_node("Monster")
	# Position monster in front of table
	monster.global_position = Vector3(0.48, 0.0, 1.0)
	# Target behind table
	var target := Vector3(0.48, 0.0, -4.5)

	var path: Array[Vector3] = monster.find_path_to(target)
	assert(path.size() >= 3, "Path must contain multiple waypoints navigating around obstacle")

	# Verify path does not route straight through solid table cells
	var navigated_around := false
	for pt in path:
		# If any waypoint deviates sideways from X = 0.48 by > 0.6m, it successfully steered around the table
		if absf(pt.x - 0.48) > 0.6:
			navigated_around = true
			break
	assert(navigated_around, "A* path must detour laterally around table obstacle")
	print("PASS: A* calculated detour path around obstacles rather than straight through")

	world.queue_free()
	await get_tree().process_frame

func test_echolocation_investigate_path() -> void:
	print("\n[Test Nav 4] Echolocation Investigate generates A* Path to sound")
	var world_scene = load("res://scenes/level/test_world.tscn")
	var world = world_scene.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame

	var monster = world.get_node("Monster")
	var player = world.get_node("Player")

	monster.global_position = Vector3(0.0, 0.0, 0.0)
	var sound_pos := Vector3(2.0, 0.0, 2.0) # Jarak 2.8m, dalam hearing_radius 6.0m

	# Emit echolocation within hearing radius
	player.echolocation_made.emit(sound_pos, 8.0)

	assert(monster.current_state == MonsterScript.State.INVESTIGATE, "Monster must enter INVESTIGATE")
	assert(monster.target_position == sound_pos, "Target position should match sound origin")
	assert(monster.current_path.size() > 0, "Monster must have generated an A* path to sound origin")
	print("PASS: Echolocation triggers path generation to sound origin")

	world.queue_free()
	await get_tree().process_frame

func test_chase_pathfinding_and_smoothing() -> void:
	print("\n[Test Nav 5] Chase Mode continuous tracking and Raycast Smoothing")
	var world_scene = load("res://scenes/level/test_world.tscn")
	var world = world_scene.instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().physics_frame

	var monster = world.get_node("Monster")
	var player = world.get_node("Player")

	monster.global_position = Vector3(0.0, 0.0, 2.0)
	player.global_position = Vector3(0.0, 0.0, -4.0)

	monster.trigger_direct_shine_chase()
	assert(monster.current_state == MonsterScript.State.CHASE)

	# Run a physics frame to let monster calculate path and move
	monster._physics_process(0.1)
	assert(monster.velocity.length() > 0.0, "Monster should be moving along path toward player")
	assert(monster.current_path.size() > 0, "Monster should have active chase path")

	# Test raycast smoothing helper
	var raw_dir := Vector3(0.0, 0.0, -1.0)
	var smoothed_dir: Vector3 = monster._apply_raycast_smoothing(raw_dir)
	assert(smoothed_dir.is_normalized(), "Smoothed direction should be normalized")

	print("PASS: Chase mode actively updates shortest path with Raycast smoothing")
	world.queue_free()
	await get_tree().process_frame
