extends Node

const MonsterScript = preload("res://scripts/characters/monster.gd")

func _ready() -> void:
	print("--- BEGIN TEST MONSTER VISUALS ---")
	test_visual_material_properties()
	test_fallback_loader()
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
