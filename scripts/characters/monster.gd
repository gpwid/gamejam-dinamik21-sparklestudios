extends CharacterBody3D
class_name Monster

# ==============================================================================
# ENUM STATES & SOURCES
# ==============================================================================
enum State {
	PATROL,
	INVESTIGATE,
	CHASE,
	JUMPSCARE
}

enum ChaseSource {
	NONE,
	OVERHEAT,
	DIRECT_SHINE
}

# ==============================================================================
# CONFIGURABLE EXPORT VARIABLES
# ==============================================================================
@export_group("Monster Movement")
@export var patrol_speed: float = 1.8
@export var investigate_speed: float = 2.2
@export var chase_speed: float = 4.2
@export var acceleration: float = 12.0
@export var gravity: float = 9.8

@export_group("Patrol Configuration")
@export var patrol_bounds_min: Vector2 = Vector2(-7.0, -7.5) # Batas lantai X min, Z min
@export var patrol_bounds_max: Vector2 = Vector2(7.0, 7.0)   # Batas lantai X max, Z max
@export var patrol_waypoints: Array[Vector3] = []            # Titik-titik rute patroli opsional
@export var patrol_wait_min: float = 1.0                     # Jeda diam minimal saat sampai di titik tujuan (detik)
@export var patrol_wait_max: float = 2.0                     # Jeda diam maksimal saat sampai di titik tujuan (detik)
@export var wall_stuck_timeout: float = 1.0                  # Jika mentok menabrak rintangan > 1.0s, ganti titik tujuan
@export var min_patrol_distance: float = 3.0                 # Jarak minimal titik patroli baru dari posisi saat ini

@export_group("Detection & Ranges")
@export var jumpscare_distance: float = 1.4
@export var patrol_radius: float = 10.0
@export var hearing_radius: float = 6.0
@export var direct_trigger_chase_duration: float = 18.0
@export var direct_shine_cone_tolerance: float = 0.05

@export_group("Timers & Delays")
@export var patrol_wait_time: float = 1.5
@export var investigate_wait_time: float = 2.0
@export var jumpscare_delay: float = 0.8

@export_group("Visual Settings")
@export var monster_width: float = 1.2
@export var monster_height: float = 2.0

@export_group("Audio")
@export var scream_sound: AudioStream = preload("res://assets/audio/sfx/trigger_scream.wav")

# ==============================================================================
# NODE REFERENCES
# ==============================================================================
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var sprite: Sprite3D = get_node_or_null("Sprite3D")
@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
@onready var scream_player: AudioStreamPlayer3D = get_node_or_null("ScreamPlayer")
@onready var game_over_ui: CanvasLayer = get_node_or_null("GameOverUI")

# ==============================================================================
# RUNTIME STATE
# ==============================================================================
var current_state: State = State.PATROL
var chase_source: ChaseSource = ChaseSource.NONE

var spawn_position: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var state_timer: float = 0.0
var direct_chase_timer: float = 0.0
var stuck_timer: float = 0.0
var is_waiting: bool = false
var has_screamed_chase: bool = false
var current_waypoint_index: int = -1

var player: Node3D = null

# ==============================================================================
# INITIALIZATION
# ==============================================================================
func _ready() -> void:
	add_to_group("monster")
	spawn_position = global_position

	_init_visuals()
	_init_audio()
	_init_default_waypoints()
	_find_player()
	target_position = get_next_patrol_target()

func _init_visuals() -> void:
	var tex := load_monster_texture()
	var mat := _setup_visual_material(tex)

	if mesh_instance:
		mesh_instance.material_override = mat
		mesh_instance.position = Vector3(0.0, monster_height * 0.5, 0.0)
		mesh_instance.layers = 1
		if mesh_instance.mesh is QuadMesh:
			var q := mesh_instance.mesh as QuadMesh
			q.size = Vector2(monster_width, monster_height)
		elif mesh_instance.mesh == null:
			var q := QuadMesh.new()
			q.size = Vector2(monster_width, monster_height)
			mesh_instance.mesh = q

	if sprite:
		sprite.material_override = mat
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.shaded = true
		sprite.texture = tex
		sprite.position = Vector3(0.0, monster_height * 0.5, 0.0)
		sprite.layers = 1

func load_monster_texture() -> Texture2D:
	var tex: Texture2D = null
	var paths: Array[String] = [
		"res://assets/placeholders/monster.jpeg",
		"res://assets/textures/placeholders/monster.jpeg"
	]

	# 1. Pemuatan via ResourceLoader
	for p in paths:
		if ResourceLoader.exists(p):
			tex = ResourceLoader.load(p) as Texture2D
			if tex != null:
				print("[MONSTER] Tekstur berhasil dimuat via ResourceLoader: ", p)
				return tex

	# 2. Fallback: Pemuatan langsung dari file (Image.load_from_file)
	for p in paths:
		var global_p := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(p) or FileAccess.file_exists(global_p):
			var img := Image.new()
			var err := img.load(global_p)
			if err != OK:
				img = Image.load_from_file(global_p)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
				print("[MONSTER] Tekstur berhasil dimuat via Image.load_from_file: ", global_p)
				return tex

	# 3. Fallback: Prosedural Putih Terang
	print("[MONSTER WARNING] Gagal memuat file gambar monster. Membuat tekstur kotak putih prosedural sebagai fallback!")
	var fallback_img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	fallback_img.fill(Color(0.95, 0.95, 0.95, 1.0))
	for x in range(128):
		for y in range(128):
			if x < 4 or x > 123 or y < 4 or y > 123 or (x > 60 and x < 68) or (y > 60 and y < 68):
				fallback_img.set_pixel(x, y, Color(0.85, 0.1, 0.1, 1.0))
	tex = ImageTexture.create_from_image(fallback_img)
	return tex

func _setup_visual_material(tex: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 1.0
	mat.metallic = 0.0

	# MATIKAN TOTAL EMISSION & UNSHADED:
	# Dalam kegelapan saat senter OFF, monster 100% hitam pekat (#000000) menyatu penuh dengan kegelapan layar.
	# Saat terkena ekolokasi (senter OFF), hanya outline siluetnya saja yang menyala, sedangkan tekstur gambar tetap tidak terlihat.
	mat.emission_enabled = false
	mat.emission = Color.BLACK
	mat.emission_energy_multiplier = 0.0
	return mat

func _init_default_waypoints() -> void:
	if patrol_waypoints.is_empty():
		var y_lvl := global_position.y
		patrol_waypoints = [
			Vector3(-4.5, y_lvl, -4.5),
			Vector3(4.5, y_lvl, -5.5),
			Vector3(5.0, y_lvl, 2.0),
			Vector3(0.0, y_lvl, 4.5),
			Vector3(-5.0, y_lvl, 2.5),
			Vector3(-2.0, y_lvl, -1.5),
			Vector3(3.0, y_lvl, -1.5)
		]

func _init_audio() -> void:
	if scream_player == null:
		scream_player = AudioStreamPlayer3D.new()
		scream_player.name = "ScreamPlayer"
		scream_player.max_distance = 50.0
		add_child(scream_player)
	if scream_player.stream == null and scream_sound != null:
		scream_player.stream = scream_sound

func _find_player() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			_set_player(p)
			return

	var root_scene = get_tree().current_scene
	if root_scene:
		var p = root_scene.find_child("Player", true, false)
		if p and is_instance_valid(p) and not p.is_queued_for_deletion():
			_set_player(p)
			return

	var root_node = get_tree().root
	if root_node:
		var p2 = root_node.find_child("Player", true, false)
		if p2 and is_instance_valid(p2) and not p2.is_queued_for_deletion():
			_set_player(p2)

func _set_player(p: Node) -> void:
	if player == p:
		return
	player = p
	if player.has_signal("echolocation_made") and not player.echolocation_made.is_connected(_on_echolocation_made):
		player.echolocation_made.connect(_on_echolocation_made)
	if player.has_signal("flashlight_exploded") and not player.flashlight_exploded.is_connected(_on_player_flashlight_overheated):
		player.flashlight_exploded.connect(_on_player_flashlight_overheated)

# ==============================================================================
# PHYSICS PROCESS & STATE MACHINE
# ==============================================================================
func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player.is_queued_for_deletion():
		_find_player()

	# Cek deteksi sorot langsung senter player (Kondisi B)
	var is_lit := check_direct_flashlight_shine()
	if is_lit:
		if current_state == State.PATROL or current_state == State.INVESTIGATE:
			trigger_direct_shine_chase()
		elif current_state == State.CHASE and chase_source == ChaseSource.DIRECT_SHINE:
			direct_chase_timer = direct_trigger_chase_duration

	match current_state:
		State.PATROL:
			_update_patrol(delta)
		State.INVESTIGATE:
			_update_investigate(delta)
		State.CHASE:
			_update_chase(delta)
		State.JUMPSCARE:
			_update_jumpscare(delta)

# ==============================================================================
# PATROL LOGIC
# ==============================================================================
func _update_patrol(delta: float) -> void:
	# 1. Fase Diam Sebentar (1.0 - 2.0 detik) saat sampai di titik tujuan
	if is_waiting:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = -0.1
		move_and_slide()

		state_timer -= delta
		if state_timer <= 0.0:
			is_waiting = false
			stuck_timer = 0.0
			target_position = get_next_patrol_target()
			print("[MONSTER] Jeda patroli selesai. Menuju ke titik patroli baru: ", target_position)
		return

	# 2. Cek apakah sudah sampai di titik tujuan patroli (jarak horizontal <= 0.7m)
	var diff := target_position - global_position
	diff.y = 0.0
	var dist := diff.length()
	if dist <= 0.7:
		is_waiting = true
		state_timer = randf_range(patrol_wait_min, patrol_wait_max)
		stuck_timer = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		print("[MONSTER] Sampai di titik tujuan patroli %s. Diam sebentar selama %s detik..." % [target_position, snapped(state_timer, 0.1)])
		return

	# 3. Deteksi tabrakan dinding/objek (is_on_wall()):
	# Jika monster mentok menabrak objek/tembok selama > 1.0 detik saat berjalan,
	# langsung ganti arah ke titik patroli lain agar tidak jalan di tempat!
	var horiz_vel := Vector2(velocity.x, velocity.z).length()
	var real_vel := get_real_velocity()
	var real_speed := Vector2(real_vel.x, real_vel.z).length()

	if is_on_wall() or (horiz_vel > 0.4 and real_speed < 0.12):
		stuck_timer += delta
		if stuck_timer >= wall_stuck_timeout:
			stuck_timer = 0.0
			target_position = get_next_patrol_target()
			print("[MONSTER] Mentok menabrak rintangan > %s detik! Mengalihkan ke titik patroli baru: %s" % [wall_stuck_timeout, target_position])
			return
	else:
		stuck_timer = maxf(0.0, stuck_timer - delta * 0.5)

	# 4. Berjalan aktif menuju target_position dengan patrol_speed
	_move_towards(target_position, patrol_speed, delta)

func get_next_patrol_target() -> Vector3:
	if not patrol_waypoints.is_empty():
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
		var wp := patrol_waypoints[current_waypoint_index]
		wp.x = clampf(wp.x, patrol_bounds_min.x, patrol_bounds_max.x)
		wp.z = clampf(wp.z, patrol_bounds_min.y, patrol_bounds_max.y)
		wp.y = global_position.y
		return wp

	var current_pos_2d := Vector2(global_position.x, global_position.z)
	for i in range(12):
		var rx := randf_range(patrol_bounds_min.x, patrol_bounds_max.x)
		var rz := randf_range(patrol_bounds_min.y, patrol_bounds_max.y)
		if current_pos_2d.distance_to(Vector2(rx, rz)) >= min_patrol_distance:
			return Vector3(rx, global_position.y, rz)

	var fallback_x := randf_range(patrol_bounds_min.x, patrol_bounds_max.x)
	var fallback_z := randf_range(patrol_bounds_min.y, patrol_bounds_max.y)
	return Vector3(fallback_x, global_position.y, fallback_z)

func _pick_new_patrol_target() -> void:
	target_position = get_next_patrol_target()

# ==============================================================================
# INVESTIGATE LOGIC (REAKSI SUARA EKOLOKASI)
# ==============================================================================
func _update_investigate(delta: float) -> void:
	if is_waiting:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()

		state_timer -= delta
		if state_timer <= 0.0:
			_enter_patrol()
		return

	var diff := target_position - global_position
	diff.y = 0.0
	if diff.length() <= 0.8:
		is_waiting = true
		state_timer = investigate_wait_time
		return

	_move_towards(target_position, investigate_speed, delta)

func _on_echolocation_made(sound_origin: Vector3, radius: float) -> void:
	if current_state == State.CHASE or current_state == State.JUMPSCARE:
		return

	var dist := global_position.distance_to(sound_origin)
	if dist <= hearing_radius:
		current_state = State.INVESTIGATE
		target_position = sound_origin
		is_waiting = false
		state_timer = 0.0
		print("[MONSTER] Mendengar suara ekolokasi di %s (jarak: %s m). Mendatangi untuk menyelidiki..." % [sound_origin, snapped(dist, 0.1)])

# ==============================================================================
# CHASE LOGIC (KONDISI A & KONDISI B)
# ==============================================================================
func _update_chase(delta: float) -> void:
	if not is_instance_valid(player):
		_enter_patrol()
		return

	var player_pos := player.global_position
	var dist_to_player := global_position.distance_to(player_pos)

	# Jumpscare check
	if dist_to_player <= jumpscare_distance:
		_enter_jumpscare()
		return

	if chase_source == ChaseSource.DIRECT_SHINE:
		direct_chase_timer -= delta
		if direct_chase_timer <= 0.0:
			print("[MONSTER] Durasi pengejaran sorot senter habis. Pemain berhasil kabur! Kembali ke Patroli.")
			_enter_patrol()
			return
	elif chase_source == ChaseSource.OVERHEAT:
		var is_player_triggered: bool = false
		if "is_triggered" in player:
			is_player_triggered = player.is_triggered
		if not is_player_triggered:
			print("[MONSTER] Masa kejaran Overheat selesai (Exposure 0%%). Kembali ke Patroli.")
			_enter_patrol()
			return

	_move_towards(player_pos, chase_speed, delta)

func trigger_direct_shine_chase() -> void:
	current_state = State.CHASE
	chase_source = ChaseSource.DIRECT_SHINE
	direct_chase_timer = direct_trigger_chase_duration
	is_waiting = false
	print("[MONSTER] CHASE AKTIF: Monster tersorot senter langsung (Kondisi B)! Durasi kejar: %s detik." % direct_trigger_chase_duration)
	_play_scream()

func _on_player_flashlight_overheated(player_pos: Vector3) -> void:
	if current_state == State.JUMPSCARE:
		return
	if current_state == State.CHASE:
		# Jika sedang dalam pengejaran Kondisi B, beralih ke sumber OVERHEAT tanpa dobel scream/reset
		chase_source = ChaseSource.OVERHEAT
		return

	trigger_overheat_chase()

func trigger_overheat_chase() -> void:
	current_state = State.CHASE
	chase_source = ChaseSource.OVERHEAT
	is_waiting = false
	print("[MONSTER] CHASE AKTIF: Parameter senter overheat 100% (Kondisi A)!")
	if not has_screamed_chase:
		_play_scream()
		has_screamed_chase = true

# ==============================================================================
# DETEKSI SOROT LANGSUNG SENTER (RAYCAST & CONE CHECK)
# ==============================================================================
func check_direct_flashlight_shine() -> bool:
	if not is_inside_tree():
		return false
	if not is_instance_valid(player):
		return false

	var fl: SpotLight3D = null
	if "flashlight" in player and player.flashlight is SpotLight3D:
		fl = player.flashlight
	if not fl:
		return false

	var is_on: bool = false
	if "is_flashlight_on" in player:
		is_on = player.is_flashlight_on
	elif fl.visible and fl.light_energy > 0.05:
		is_on = true

	if not is_on or not fl.visible or fl.light_energy <= 0.05 or fl.spot_range <= 0.1:
		return false

	var monster_chest := global_position + Vector3(0.0, 1.0, 0.0)
	var fl_pos := fl.global_position
	var to_monster := monster_chest - fl_pos
	var dist := to_monster.length()

	if dist > fl.spot_range:
		return false

	var fl_forward := -fl.global_transform.basis.z.normalized()
	var to_monster_dir := to_monster.normalized()
	var angle := fl_forward.angle_to(to_monster_dir)
	var max_cone_angle := deg_to_rad(fl.spot_angle + direct_shine_cone_tolerance)
	if angle > max_cone_angle:
		return false

	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return false

	var query := PhysicsRayQueryParameters3D.create(fl_pos, monster_chest)
	if player is CollisionObject3D:
		query.exclude = [player.get_rid()]

	var res := space_state.intersect_ray(query)
	if res.is_empty():
		return true
	if res.collider == self:
		return true
	if res.collider.get_parent() == self or (res.collider.owner and res.collider.owner == self):
		return true

	return false

# ==============================================================================
# JUMPSCARE & GAME OVER
# ==============================================================================
func _enter_jumpscare() -> void:
	current_state = State.JUMPSCARE
	velocity = Vector3.ZERO
	state_timer = jumpscare_delay
	print("[MONSTER] JUMPSCARE! Monster menangkap player pada jarak %s m." % snapped(global_position.distance_to(player.global_position), 0.1))
	_play_scream()
	if player and player.has_method("trigger_jumpscare"):
		player.trigger_jumpscare(self)

func _update_jumpscare(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()

	if state_timer > 0.0:
		state_timer -= delta
		if state_timer <= 0.0:
			if game_over_ui and game_over_ui.has_method("show_game_over"):
				game_over_ui.show_game_over()

# ==============================================================================
# LOCOMOTION & HELPERS
# ==============================================================================
func _move_towards(target: Vector3, speed: float, delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	var diff := target - global_position
	diff.y = 0.0
	var dist := diff.length()

	if dist > 0.05:
		var desired_dir := diff.normalized()
		if is_on_wall():
			var wall_norm := get_wall_normal()
			wall_norm.y = 0.0
			if wall_norm.length() > 0.01:
				var slide_dir := desired_dir.slide(wall_norm.normalized()).normalized()
				if slide_dir.length() > 0.01:
					desired_dir = slide_dir

		velocity.x = move_toward(velocity.x, desired_dir.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, desired_dir.z * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)

	move_and_slide()

func _enter_patrol() -> void:
	current_state = State.PATROL
	chase_source = ChaseSource.NONE
	has_screamed_chase = false
	is_waiting = false
	stuck_timer = 0.0
	target_position = get_next_patrol_target()

func _play_scream() -> void:
	if scream_player:
		if scream_player.stream == null and scream_sound != null:
			scream_player.stream = scream_sound
		if scream_player.stream and not scream_player.playing:
			scream_player.pitch_scale = randf_range(0.94, 1.06)
			scream_player.play()
