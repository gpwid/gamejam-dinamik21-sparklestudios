extends Node3D

@onready var ui: CanvasLayer = $UI
@onready var fnaf_spot_light: SpotLight3D = ($Stage3D/SpotLight if has_node("Stage3D/SpotLight") else ($Stage3D/FNAF_SpotLight if has_node("Stage3D/FNAF_SpotLight") else null)) as SpotLight3D
@onready var monster_node: Node3D = $Stage3D/Monster
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var camera_3d: Camera3D = $Camera3D
@onready var outline_pass: MeshInstance3D = $Camera3D/OutlinePass

var outline_mat: ShaderMaterial = null
var base_light_pos: Vector3
var base_light_energy: float = 2.4
var base_monster_rot: Vector3
var light_anim_time: float = 0.0
var twitch_timer: float = 3.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if fnaf_spot_light:
		base_light_pos = fnaf_spot_light.position
		base_light_energy = fnaf_spot_light.light_energy
	if monster_node:
		base_monster_rot = monster_node.rotation_degrees

	_apply_noir_shader_to_monster()

	if outline_pass:
		outline_mat = outline_pass.get_active_material(0) as ShaderMaterial
		if outline_mat and fnaf_spot_light:
			outline_mat.set_shader_parameter("flashlight_on", true)
			_sync_outline_light()

	if ui and ui.has_signal("brightness_changed"):
		ui.brightness_changed.connect(_on_brightness_changed)

	_init_monster_animation()

func _apply_noir_shader_to_monster() -> void:
	if monster_node == null:
		return
	var body_mat := load("res://assets/material/noir_monster.tres") as Material
	var face_mat := load("res://assets/material/noir_monster_face.tres") as Material
	if body_mat == null or face_mat == null:
		return
	_apply_monster_mats_recursive(monster_node, body_mat, face_mat)

func _apply_monster_mats_recursive(node: Node, body_mat: Material, face_mat: Material) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		mi.material_override = null
		if mi.mesh:
			var surf_count := mi.mesh.get_surface_count()
			for s_idx in range(surf_count):
				if mi.name == "Plane" and s_idx == 1:
					mi.set_surface_override_material(s_idx, face_mat)
				else:
					mi.set_surface_override_material(s_idx, body_mat)
	for child in node.get_children():
		_apply_monster_mats_recursive(child, body_mat, face_mat)

func _process(delta: float) -> void:
	if fnaf_spot_light:
		light_anim_time += delta
		var sway_x := sin(light_anim_time * 0.75) * 0.12
		var sway_y := cos(light_anim_time * 0.95) * 0.08
		fnaf_spot_light.position = base_light_pos + Vector3(sway_x, sway_y, 0.0)

		var flicker := sin(light_anim_time * 3.2) * 0.15 + cos(light_anim_time * 5.7) * 0.08
		if randf() < 0.025:
			flicker -= 0.6
		fnaf_spot_light.light_energy = maxf(0.8, base_light_energy + flicker)
		_sync_outline_light()

	twitch_timer -= delta
	if twitch_timer <= 0.0:
		twitch_timer = randf_range(3.5, 6.5)
		_trigger_monster_twitch()

func _sync_outline_light() -> void:
	if outline_mat and fnaf_spot_light and camera_3d:
		outline_mat.set_shader_parameter("flashlight_on", true)
		outline_mat.set_shader_parameter("flashlight_view_pos", camera_3d.to_local(fnaf_spot_light.global_position))
		var fwd := -fnaf_spot_light.global_transform.basis.z.normalized()
		outline_mat.set_shader_parameter("flashlight_view_dir", camera_3d.global_basis.inverse() * fwd)
		outline_mat.set_shader_parameter("flashlight_cos_angle", cos(deg_to_rad(fnaf_spot_light.spot_angle)))
		outline_mat.set_shader_parameter("flashlight_range", fnaf_spot_light.spot_range)

func _init_monster_animation() -> void:
	if monster_node == null:
		return
	var anim_player: AnimationPlayer = monster_node.get_node_or_null("AnimationPlayer")
	if anim_player:
		for anim_name in anim_player.get_animation_list():
			var anim := anim_player.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
		if anim_player.has_animation("idle"):
			anim_player.play("idle")
		elif anim_player.get_animation_list().size() > 0:
			anim_player.play(anim_player.get_animation_list()[0])

func _trigger_monster_twitch() -> void:
	if monster_node == null:
		return
	var anim_player: AnimationPlayer = monster_node.get_node_or_null("AnimationPlayer")
	if anim_player and not anim_player.is_playing():
		if anim_player.has_animation("idle"):
			anim_player.play("idle")
		elif anim_player.get_animation_list().size() > 0:
			anim_player.play(anim_player.get_animation_list()[0])

	var twitch_rot := base_monster_rot + Vector3(randf_range(-3.5, 3.5), randf_range(-5.5, 5.5), randf_range(-2.5, 2.5))
	var tween := create_tween()
	tween.tween_property(monster_node, "rotation_degrees", twitch_rot, 0.07)
	tween.tween_property(monster_node, "rotation_degrees", base_monster_rot, 0.15).set_delay(0.05)

func _on_brightness_changed(val: float) -> void:
	if world_env and world_env.environment:
		var exp_factor := 0.4 + (val / 100.0) * 1.4
		world_env.environment.tonemap_exposure = exp_factor
