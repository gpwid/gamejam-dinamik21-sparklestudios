extends CanvasLayer
class_name DebugOverlay

@onready var top_left_margin: MarginContainer = $TopLeftMargin
@onready var stats_panel: PanelContainer = $TopLeftMargin/VBoxContainer/StatsPanel
@onready var fps_label: Label = $TopLeftMargin/VBoxContainer/StatsPanel/VBoxStats/FpsLabel
@onready var state_label: Label = $TopLeftMargin/VBoxContainer/StatsPanel/VBoxStats/StateLabel
@onready var dist_label: Label = $TopLeftMargin/VBoxContainer/StatsPanel/VBoxStats/DistLabel
@onready var los_label: Label = $TopLeftMargin/VBoxContainer/StatsPanel/VBoxStats/LosLabel
@onready var target_label: Label = $TopLeftMargin/VBoxContainer/StatsPanel/VBoxStats/TargetLabel
@onready var breath_label: Label = $TopLeftMargin/VBoxContainer/StatsPanel/VBoxStats/BreathLabel

var is_debug_active: bool = false
var monster: Monster = null
var player: CharacterBody3D = null

func _ready() -> void:
	add_to_group("debug_overlay")
	layer = 120
	if top_left_margin:
		top_left_margin.visible = false
	_update_ui_state()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3 or event.keycode == KEY_F1:
			_toggle_debug()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F4:
			auto_activate_switches()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F5:
			teleport_to_exit_door()
			get_viewport().set_input_as_handled()

func auto_activate_switches() -> void:
	var switches := get_tree().get_nodes_in_group("switch")
	if switches.is_empty():
		print("[DEBUG] Tidak ada saklar di dalam map.")
		return
	
	print("[DEBUG F4] Mengaktifkan semua %d saklar secara otomatis..." % switches.size())
	_ensure_player_ref()
	for sw in switches:
		if sw is FacilitySwitch and not sw.is_on:
			sw.interact(player)

func teleport_to_exit_door() -> void:
	_ensure_player_ref()
	var exit_door := get_tree().get_first_node_in_group("exit_door") as ExitDoor
	if not exit_door:
		exit_door = get_tree().root.find_child("ExitDoor", true, false) as ExitDoor
	
	if not exit_door:
		print("[DEBUG F5] ExitDoor tidak ditemukan di scene.")
		return
	
	if player and is_instance_valid(player):
		# Pintu berada di exit_door.global_position.
		# Di door.tscn, ruangan cahaya berada di arah +Z (EscapeTrigger z=12).
		# Koridor menghadap pintu berada di arah -Z (mundur 3.5 meter dari pintu).
		var door_forward: Vector3 = (exit_door.global_transform.basis * Vector3(0, 0, 1)).normalized()
		var target_pos: Vector3 = exit_door.global_position - door_forward * 3.5
		target_pos.y = maxf(exit_door.global_position.y + 0.1, 0.2)
		
		player.global_position = target_pos
		player.velocity = Vector3.ZERO
		
		# Arahkan pandangan pemain langsung ke pintu
		var to_door := (exit_door.global_position - target_pos).normalized()
		player.rotation.y = atan2(-to_door.x, -to_door.z)
		if player.has_node("Head"):
			player.get_node("Head").rotation.x = 0.0
		
		print("[DEBUG F5] Pemain berhasil diteleportasi ke depan Exit Door (%s)!" % target_pos)

func _toggle_debug() -> void:
	is_debug_active = !is_debug_active
	_ensure_monster_ref()
	if monster and is_instance_valid(monster):
		monster.debug_enabled = is_debug_active
	
	# Update bounding box visual semua saklar di level
	for sw in get_tree().get_nodes_in_group("switch"):
		if sw.has_method("set_debug_enabled"):
			sw.set_debug_enabled(is_debug_active)
			
	_update_ui_state()

func _update_ui_state() -> void:
	if top_left_margin:
		top_left_margin.visible = is_debug_active

func _process(delta: float) -> void:
	if not is_debug_active:
		return

	# 1. Update Frame Rate
	var fps := Engine.get_frames_per_second()
	var frame_ms := delta * 1000.0
	if fps_label:
		fps_label.text = "FPS: %d (%.1f ms)" % [fps, frame_ms]

	# 2. Update Monster Info
	_ensure_monster_ref()
	_ensure_player_ref()

	if monster and is_instance_valid(monster):
		if not monster.debug_enabled:
			monster.debug_enabled = true

		# State
		if state_label:
			var s_name := "PATROL"
			match monster.current_state:
				Monster.State.PATROL:
					s_name = "PATROL"
				Monster.State.INVESTIGATE:
					s_name = "INVESTIGATE"
				Monster.State.CHASE:
					s_name = "CHASE"
				Monster.State.JUMPSCARE:
					s_name = "JUMPSCARE"
			state_label.text = "STATE: %s" % s_name

		# Distance
		if dist_label:
			if player and is_instance_valid(player):
				var d := monster.global_position.distance_to(player.global_position)
				dist_label.text = "JARAK: %.1f m" % d
			else:
				dist_label.text = "JARAK: N/A"

		# Line of Sight
		if los_label:
			if player and is_instance_valid(player):
				var has_los: bool = monster._has_line_of_sight(player.global_position)
				if has_los:
					los_label.text = "PANDANGAN: TERLIHAT (CLEAR)"
				else:
					los_label.text = "PANDANGAN: TERHALANG DINDING"
			else:
				los_label.text = "PANDANGAN: N/A"

		# Target & Path
		if target_label:
			var rem_path := monster.current_path.size() - monster.current_path_index
			rem_path = maxi(0, rem_path)
			target_label.text = "TARGET: (%.1f, %.1f) | PATH: %d node" % [
				monster.target_position.x,
				monster.target_position.z,
				rem_path
			]
	else:
		if state_label:
			state_label.text = "STATE: MONSTER TIDAK DITEMUKAN"

	# 3. Update Player Status
	if breath_label:
		if player and is_instance_valid(player) and "is_holding_breath" in player:
			if player.is_holding_breath:
				breath_label.text = "NAPAS: MENAHAN NAPAS (SHIFT)"
			else:
				breath_label.text = "NAPAS: NORMAL (BERNAPAS)"

func _ensure_monster_ref() -> void:
	if monster == null or not is_instance_valid(monster):
		monster = get_tree().get_first_node_in_group("monster") as Monster

func _ensure_player_ref() -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if player == null and monster and is_instance_valid(monster):
			player = monster.player
