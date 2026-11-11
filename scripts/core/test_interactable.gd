extends Node3D

@export var target_visual: Node3D

var is_toggled: bool = false
var original_scale: Vector3 = Vector3.ONE
var original_rotation: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("interactable")
	for child in get_children():
		if child is CollisionObject3D:
			child.add_to_group("interactable")

	if not target_visual:
		target_visual = self

	original_scale = target_visual.scale
	original_rotation = target_visual.rotation_degrees

func interact(player: Node = null) -> void:
	# Pastikan target_visual terinisialisasi
	if not target_visual:
		target_visual = self
		original_scale = target_visual.scale
		original_rotation = target_visual.rotation_degrees

	# Jika player diteruskan dan senternya mati, alihkan ke interaksi gelap
	if player and ("flashlight" in player):
		if not player.flashlight.visible or player.is_overheated:
			interact_in_dark(player)
			return

	print("Berhasil berinteraksi dengan objek!")
	is_toggled = not is_toggled

	var target_scale: Vector3 = original_scale * (1.35 if is_toggled else 1.0)
	var target_rot_y: float = original_rotation.y + (45.0 if is_toggled else 0.0)

	if is_inside_tree():
		var tween := create_tween()
		if tween:
			tween.set_parallel(true)
			var tw1 = tween.tween_property(target_visual, "scale", target_scale, 0.25)
			if tw1:
				tw1.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			var tw2 = tween.tween_property(target_visual, "rotation_degrees:y", target_rot_y, 0.25)
			if tw2:
				tw2.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		target_visual.scale = target_scale
		target_visual.rotation_degrees.y = target_rot_y

func interact_in_dark(player: Node = null) -> void:
	print("Gelap gulita! Nyalakan senter untuk berinteraksi.")
	if player and ("landing_spring_vel" in player):
		player.landing_spring_vel -= 0.7
