extends Node3D
class_name ExitDoor

signal door_opened()
signal player_escaped()

@export var is_open: bool = false

@onready var left_door: Node3D = $door/Cylinder_014
@onready var right_door: Node3D = $door/Cube_020
@onready var door_collider: CollisionShape3D = get_node_or_null("StaticBody3D/CollisionShape3D")
@onready var escape_trigger: Area3D = get_node_or_null("EscapeTrigger")
@onready var exit_light: SpotLight3D = get_node_or_null("ExitLight")
@onready var open_audio: AudioStreamPlayer3D = get_node_or_null("DoorOpenAudio")

var left_closed_rot_y: float = 0.0
var right_closed_rot_y: float = 0.0

func _ready() -> void:
	add_to_group("exit_door")
	if left_door:
		left_closed_rot_y = left_door.rotation.y
	if right_door:
		right_closed_rot_y = right_door.rotation.y
	if escape_trigger:
		escape_trigger.body_entered.connect(_on_escape_trigger_entered)
	if exit_light:
		exit_light.visible = false
		exit_light.light_energy = 0.0

func open() -> void:
	if is_open:
		return
	is_open = true
	
	# Matikan collider penghalang agar pemain bisa lewat
	if door_collider:
		door_collider.set_deferred("disabled", true)
	
	# Suara pintu terbuka
	if open_audio:
		open_audio.play()
	
	# Animasi membuka kedua daun pintu dan menyemburkan cahaya putih
	var tween := create_tween().set_parallel(true)
	if left_door:
		var target_left_y := left_closed_rot_y - deg_to_rad(95.0)
		tween.tween_property(left_door, "rotation:y", target_left_y, 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if right_door:
		var target_right_y := right_closed_rot_y + deg_to_rad(95.0)
		tween.tween_property(right_door, "rotation:y", target_right_y, 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if exit_light:
		exit_light.visible = true
		exit_light.light_energy = 0.0
		tween.tween_property(exit_light, "light_energy", 12.0, 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	door_opened.emit()
	print("[EXIT DOOR] Pintu keluar telah TERBUKA! Ruangan cahaya aktif.")

func _on_escape_trigger_entered(body: Node) -> void:
	if not is_open:
		return
	if body.is_in_group("player") or body.name == "Player":
		print("[VICTORY] Pemain berhasil mencapai pintu keluar dan MELARIKAN DIRI!")
		player_escaped.emit()
