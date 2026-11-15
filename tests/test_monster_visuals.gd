extends Node

const MonsterScript = preload("res://scripts/characters/monster.gd")

func _ready() -> void:
	print("--- BEGIN TEST MONSTER VISUALS ---")
	await test_visual_material_properties()
	test_fallback_loader()
	await test_jumpscare_visual_activation_and_reset()
	print("--- ALL MONSTER VISUAL TESTS PASSED ---")
	get_tree().quit(0)

func test_visual_material_properties() -> void:
	print("\n[Test Visual 1] Check MeshInstance3D, Material, Depth Draw, and Billboard")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var monster = monster_scene.instantiate()
	add_child(monster)
	await get_tree().process_frame

	var mesh_inst: MeshInstance3D = monster.find_child("MeshInstance3D", true, false)
	assert(mesh_inst != null, "MeshInstance3D must exist on Monster")
	assert(mesh_inst.position.y == 1.0, "MeshInstance3D vertical position must be at Y = 1.0 (above floor)")
	assert(mesh_inst.layers == 1, "MeshInstance3D layers must be on Layer 1")

	var mat: StandardMaterial3D = mesh_inst.material_override as StandardMaterial3D
	assert(mat != null, "Material override must be a StandardMaterial3D")
	assert(mat.billboard_mode == BaseMaterial3D.BILLBOARD_FIXED_Y, "Billboard mode must be BILLBOARD_FIXED_Y")
	assert(mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Transparency must be DISABLED (Opaque)")
	assert(mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS, "Depth draw mode must be DEPTH_DRAW_ALWAYS")
	assert(mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "Cull mode must be CULL_DISABLED (double-sided)")
	assert(mat.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "Shading mode must be PER_PIXEL (not unshaded)")
	assert(mat.emission_enabled == false, "Emission must be disabled so monster is 100% black in dark")
	assert(mat.albedo_texture != null, "Albedo texture must be loaded")

	print("PASS: Material properties verified (Billboard=BILLBOARD_FIXED_Y, DepthDraw=DEPTH_DRAW_ALWAYS, Opaque=True, Shading=PER_PIXEL, Emission=Disabled, Layer=1, Y=1.0)")
	monster.queue_free()
	await get_tree().process_frame

func test_fallback_loader() -> void:
	print("\n[Test Visual 2] Fallback texture generation")
	var monster = MonsterScript.new()
	var tex = monster.load_monster_texture()
	assert(tex != null, "Texture must not be null")
	print("PASS: Fallback loader returned valid texture: ", tex)
	monster.free()

func test_jumpscare_visual_activation_and_reset() -> void:
	print("\n[Test Visual 3] Jumpscare Visuals (Unshaded + Emission + Jumpscare Light + Anti-Clipping Position)")
	var player_scene = load("res://scenes/characters/player.tscn")
	var monster_scene = load("res://scenes/characters/monster.tscn")
	var player = player_scene.instantiate()
	var monster = monster_scene.instantiate()
	add_child(player)
	add_child(monster)
	await get_tree().process_frame

	player.global_position = Vector3(0.0, 0.0, 0.0)
	monster.global_position = Vector3(0.0, 0.0, 1.2) # Close to player

	# Ensure flashlight is OFF
	player.is_flashlight_on = false
	player.flashlight.visible = false

	var mesh_inst: MeshInstance3D = monster.find_child("MeshInstance3D", true, false)
	var mat: StandardMaterial3D = mesh_inst.material_override as StandardMaterial3D
	assert(mat.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "Before jumpscare: shading must be PER_PIXEL (dark)")
	assert(mat.emission_enabled == false, "Before jumpscare: emission must be false")
	assert(monster.jumpscare_light != null, "JumpscareLight must exist on monster")
	assert(monster.jumpscare_light.visible == false, "Before jumpscare: JumpscareLight must be OFF")

	# Trigger Jumpscare
	monster._enter_jumpscare()

	# 1. Verify dynamic material changes to visible in dark
	assert(mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "During jumpscare: shading mode must be SHADING_MODE_UNSHADED")
	assert(mat.emission_enabled == true, "During jumpscare: emission must be enabled")
	assert(mat.emission_energy_multiplier >= 1.0, "During jumpscare: emission energy must be bright (>= 1.0)")

	# 2. Verify dedicated jumpscare spotlight/omnilight
	assert(monster.jumpscare_light.visible == true, "During jumpscare: JumpscareLight must be turned ON")
	assert(monster.jumpscare_light.light_energy > 0.0, "During jumpscare: JumpscareLight energy must be > 0.0")

	# 3. Verify camera distance and anti-clipping
	var cam_pos: Vector3 = player.camera.global_position
	var monster_pos: Vector3 = monster.global_position
	var horiz_dist := Vector2(cam_pos.x - monster_pos.x, cam_pos.z - monster_pos.z).length()
	print("Jumpscare camera-to-monster horizontal distance: %s m" % snapped(horiz_dist, 0.01))
	assert(horiz_dist >= 0.6 and horiz_dist <= 1.0, "Monster must be positioned 0.6m - 1.0m in front of camera (anti-clipping)")
	assert(player.is_jumpscared == true, "Player should be locked in jumpscare state")

	# 4. Verify Reset / Ulangi returns material to normal darkness
	monster.reset_monster_visuals()
	assert(mat.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "After reset: shading mode must return to PER_PIXEL")
	assert(mat.emission_enabled == false, "After reset: emission must return to false")
	assert(monster.jumpscare_light.visible == false, "After reset: JumpscareLight must return to false (OFF)")
	print("PASS: Jumpscare forces monster visible via Unshaded + Emission + Light, positioned safely 0.6-1.0m from camera, and resets cleanly on retry")

	player.queue_free()
	monster.queue_free()
	await get_tree().process_frame
