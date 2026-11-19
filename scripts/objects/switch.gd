extends StaticBody3D
class_name FacilitySwitch

signal switched(switch_node: FacilitySwitch)

@export var is_on: bool = false
@export var switch_id: int = 0

@onready var hum_player: AudioStreamPlayer3D = $HumPlayer
@onready var switch_player: AudioStreamPlayer3D = $SwitchPlayer
@onready var lever_mesh: Node3D = $switch/BézierCurve_002/BézierCurve_001

var initial_lever_rot_x: float = 0.0

var debug_enabled: bool = false
var debug_mesh_instance: MeshInstance3D = null
var debug_immediate_mesh: ImmediateMesh = null
var debug_material: StandardMaterial3D = null
var debug_label_3d: Label3D = null

const NOIR_PROP_MAT: Material = preload("res://assets/material/noir_prop.tres")

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("switch")
	add_to_group("interact_in_dark")

	_apply_noir_materials()
	if lever_mesh:
		initial_lever_rot_x = lever_mesh.rotation.x

	_init_debug_draw()
	var overlay = get_tree().get_first_node_in_group("debug_overlay")
	if overlay and "is_debug_active" in overlay and overlay.is_debug_active:
		set_debug_enabled(true)

	if hum_player:
		hum_player.finished.connect(func():
			if not is_on and hum_player:
				hum_player.play()
		)
		if not is_on:
			hum_player.play()

func _apply_noir_materials() -> void:
	if has_node("switch"):
		_apply_material_recursive($switch)

func _apply_material_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child != debug_mesh_instance:
			child.material_override = NOIR_PROP_MAT
		_apply_material_recursive(child)

func can_interact_in_dark() -> bool:
	return true

func interact(_player: Node = null) -> void:
	if is_on:
		return

	is_on = true

	if hum_player:
		var hum_tween := create_tween()
		hum_tween.tween_property(hum_player, "volume_db", -40.0, 0.4)
		hum_tween.tween_callback(hum_player.stop)

	if switch_player:
		switch_player.pitch_scale = randf_range(0.96, 1.04)
		switch_player.play()

	if lever_mesh:
		var tween := create_tween()
		tween.tween_property(lever_mesh, "rotation:x", initial_lever_rot_x + deg_to_rad(55.0), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	switched.emit(self)
	_update_debug_draw()

func set_debug_enabled(val: bool) -> void:
	debug_enabled = val
	if debug_mesh_instance:
		debug_mesh_instance.visible = debug_enabled
	if debug_label_3d:
		debug_label_3d.visible = debug_enabled
	if debug_enabled:
		_update_debug_draw()
	elif debug_immediate_mesh:
		debug_immediate_mesh.clear_surfaces()

func _init_debug_draw() -> void:
	debug_immediate_mesh = ImmediateMesh.new()
	debug_material = StandardMaterial3D.new()
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_material.vertex_color_use_as_albedo = true
	debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_material.no_depth_test = true
	debug_material.render_priority = 127
	debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.name = "SwitchDebugDraw3D"
	debug_mesh_instance.mesh = debug_immediate_mesh
	debug_mesh_instance.material_override = debug_material
	debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	debug_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	debug_mesh_instance.visible = debug_enabled
	add_child(debug_mesh_instance)

	debug_label_3d = Label3D.new()
	debug_label_3d.name = "SwitchDebugLabel3D"
	debug_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label_3d.no_depth_test = true
	debug_label_3d.render_priority = 127
	debug_label_3d.pixel_size = 0.007
	var custom_font = load("res://assets/fonts/HandymandiFree.ttf")
	if custom_font:
		debug_label_3d.font = custom_font
	debug_label_3d.font_size = 32
	debug_label_3d.outline_render_priority = 126
	debug_label_3d.outline_size = 6
	debug_label_3d.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	debug_label_3d.modulate = Color(1.0, 1.0, 1.0, 1.0)
	debug_label_3d.position = Vector3(0.4, 2.2, 0.7)
	debug_label_3d.visible = debug_enabled
	add_child(debug_label_3d)

func _update_debug_draw() -> void:
	if not debug_enabled or debug_immediate_mesh == null:
		return

	debug_immediate_mesh.clear_surfaces()
	debug_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, debug_material)

	# encompasses the switch box and lever
	var b_min := Vector3(-1.1, -1.6, -0.8)
	var b_max := Vector3(1.8, 1.8, 2.1)

	var p0 := Vector3(b_min.x, b_min.y, b_min.z)
	var p1 := Vector3(b_max.x, b_min.y, b_min.z)
	var p2 := Vector3(b_max.x, b_max.y, b_min.z)
	var p3 := Vector3(b_min.x, b_max.y, b_min.z)

	var p4 := Vector3(b_min.x, b_min.y, b_max.z)
	var p5 := Vector3(b_max.x, b_min.y, b_max.z)
	var p6 := Vector3(b_max.x, b_max.y, b_max.z)
	var p7 := Vector3(b_min.x, b_max.y, b_max.z)

	_add_debug_line(p0, p1)
	_add_debug_line(p1, p2)
	_add_debug_line(p2, p3)
	_add_debug_line(p3, p0)

	_add_debug_line(p4, p5)
	_add_debug_line(p5, p6)
	_add_debug_line(p6, p7)
	_add_debug_line(p7, p4)

	_add_debug_line(p0, p4)
	_add_debug_line(p1, p5)
	_add_debug_line(p2, p6)
	_add_debug_line(p3, p7)

	debug_immediate_mesh.surface_end()

	if debug_label_3d:
		var status_str := "ON" if is_on else "OFF"
		debug_label_3d.text = "[ SWITCH #%d: %s ]" % [switch_id, status_str]

func _add_debug_line(a: Vector3, b: Vector3) -> void:
	debug_immediate_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.9))
	debug_immediate_mesh.surface_add_vertex(a)
	debug_immediate_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.9))
	debug_immediate_mesh.surface_add_vertex(b)
