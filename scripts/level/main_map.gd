extends Node3D

@export var total_switches: int = 3
@export var switch_scale: float = 0.24
var switches_activated: int = 0
var game_time: float = 0.0
var is_game_finished: bool = false

@onready var player: CharacterBody3D = $Player
@onready var monster: Monster = $Monster
@onready var game_hud: GameHUD = $GameHUD
@onready var exit_door: ExitDoor = $ExitDoor
@onready var victory_ui: VictoryUI = get_node_or_null("VictoryUI")

const WALL_SOCKETS: Array[Dictionary] = [
	{ "name": "Lab Barat", "pos": Vector3(-15.99, 1.60, -2.00), "rot_y": deg_to_rad(90.0) },
	{ "name": "Lorong Tengah Barat", "pos": Vector3(-6.00, 1.60, -1.07), "rot_y": deg_to_rad(0.0) },
	{ "name": "Utara Tengah", "pos": Vector3(0.00, 1.60, -13.33), "rot_y": deg_to_rad(0.0) },
	{ "name": "Lorong Timur Tengah", "pos": Vector3(15.34, 1.60, 0.00), "rot_y": deg_to_rad(-90.0) },
	{ "name": "Ruang Timur Atas", "pos": Vector3(15.34, 1.60, 11.00), "rot_y": deg_to_rad(-90.0) },
	{ "name": "Lorong Selatan", "pos": Vector3(0.00, 1.60, 9.41), "rot_y": deg_to_rad(180.0) },
	{ "name": "Ruang Selatan Timur", "pos": Vector3(19.83, 1.60, -17.00), "rot_y": deg_to_rad(-90.0) },
	{ "name": "Lorong Timur Jauh", "pos": Vector3(27.13, 1.60, 5.00), "rot_y": deg_to_rad(-90.0) }
]

const SWITCH_SCENE: PackedScene = preload("res://scenes/objects/switch.tscn")

func _ready() -> void:
	_apply_difficulty()
	_init_hud()
	_spawn_random_switches()
	_init_exit_door()
	_start_music()

func _process(delta: float) -> void:
	if not is_game_finished:
		game_time += delta
		_update_music_ducking()

func _apply_difficulty() -> void:
	if GameManager:
		total_switches = GameManager.get_switches_count()
		if monster:
			monster.patrol_speed = GameManager.get_monster_patrol_speed()
			monster.chase_speed = GameManager.get_monster_chase_speed()
			monster.hearing_radius = 6.0 * GameManager.get_monster_hearing_multiplier()
		if player:
			player.hold_breath_drain_rate = GameManager.get_player_breath_drain_rate()
			player.stamina_recovery_rate = GameManager.get_player_recovery_rate()
		print("[level] difficulty: %s, switches: %d" % [GameManager.get_difficulty_name(), total_switches])

func _start_music() -> void:
	if GameManager:
		GameManager.play_ingame_music()

func _update_music_ducking() -> void:
	if not GameManager or is_game_finished:
		return

	var is_chase: bool = false
	if monster:
		is_chase = (monster.current_state == Monster.State.CHASE or monster.current_state == Monster.State.JUMPSCARE)

	var is_heartbeat: bool = false
	if player and monster:
		var dist: float = player.global_position.distance_to(monster.global_position)
		is_heartbeat = (dist <= player.max_heartbeat_distance)

	var is_holding_breath: bool = (player != null and player.is_holding_breath)
	var should_duck: bool = is_chase or is_heartbeat or is_holding_breath or (switches_activated >= total_switches)
	GameManager.set_ducked(should_duck)

func _init_hud() -> void:
	if game_hud:
		game_hud.set_counter(switches_activated, total_switches)
	if player and game_hud and not player.onboarding_requested.is_connected(_on_onboarding_requested):
		player.onboarding_requested.connect(_on_onboarding_requested)

func _on_onboarding_requested(type: String) -> void:
	if game_hud:
		game_hud.show_hint(type)

func _spawn_random_switches() -> void:
	var sockets := WALL_SOCKETS.duplicate()
	sockets.shuffle()

	var count := mini(total_switches, sockets.size())
	for i in range(count):
		var sock: Dictionary = sockets[i]
		var sw: FacilitySwitch = SWITCH_SCENE.instantiate()
		sw.name = "Switch_%d" % (i + 1)
		sw.switch_id = i + 1
		sw.position = sock["pos"]
		sw.rotation.y = sock["rot_y"]
		sw.scale = Vector3.ONE * switch_scale
		add_child(sw)
		sw.switched.connect(_on_switch_activated)

func _init_exit_door() -> void:
	if exit_door and not exit_door.player_escaped.is_connected(_on_player_escaped):
		exit_door.player_escaped.connect(_on_player_escaped)

func _on_switch_activated(_sw: FacilitySwitch) -> void:
	switches_activated += 1
	if game_hud:
		game_hud.set_counter(switches_activated, total_switches)

	print("[level] switches: %d/%d" % [switches_activated, total_switches])

	if switches_activated >= total_switches:
		_trigger_facility_escape()

func _trigger_facility_escape() -> void:
	print("[level] all switches activated, escape door opened")
	if exit_door:
		exit_door.open()
	if monster:
		monster.trigger_permanent_chase()
	if GameManager:
		GameManager.set_ducked(true, 0.4)

func _on_player_escaped() -> void:
	if is_game_finished:
		return
	is_game_finished = true
	print("[level] player escaped")

	if GameManager:
		GameManager.stop_music(0.5)

	if player:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		if player.has_node("HeartbeatPlayer"):
			player.get_node("HeartbeatPlayer").stop()

	if monster:
		monster.set_physics_process(false)

	if game_hud:
		game_hud.visible = false

	if victory_ui:
		victory_ui.show_victory(game_time, switches_activated, total_switches)
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
