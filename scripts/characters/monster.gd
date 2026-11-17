extends CharacterBody3D
class_name Monster

# ==============================================================================
# SIGNALS
# ==============================================================================
signal state_changed(new_state: State)
signal investigation_started(target_pos: Vector3)
signal investigation_ended()

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

@export_group("AStar Navigation & Avoidance")
@export var grid_cell_size: float = 0.4                      # Ukuran sel grid pemindaian (0.4m - 0.5m)
@export var grid_bounds_min: Vector2 = Vector2(-9.6, -9.6)   # Batas minimum area lantai (X, Z)
@export var grid_bounds_max: Vector2 = Vector2(9.6, 9.6)     # Batas maksimum area lantai (X, Z)
@export var scan_height: float = 0.6                         # Ketinggian raycast/shape scan dari lantai
@export var obstacle_margin_radius: float = 0.48             # Radius bentuk pengecekan fisika (margin badan monster)
@export var chase_recalc_interval: float = 0.25              # Interval kalkulasi ulang rute A* saat mengejar player
@export var avoidance_ray_length: float = 0.85               # Panjang raycast penghalus belokan di depan monster
@export var avoidance_ray_angle: float = 32.0                # Sudut raycast samping kiri & kanan (derajat)
@export var waypoint_reach_dist: float = 0.4                 # Jarak ambang batas mencapai waypoint rute A*

@export_group("Detection & Ranges")
@export var jumpscare_distance: float = 1.4
@export var patrol_radius: float = 10.0
@export var hearing_radius: float = 6.0
@export var direct_trigger_chase_duration: float = 4.0       # Wajib: 4.0 detik kejaran saat disorot senter
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
@export var footstep_sound: AudioStream = preload("res://assets/audio/sfx/monster_footstep.mp3")
@export var investigate_sound: AudioStream = preload("res://assets/audio/sfx/monster_investigating.wav")
@export var finish_investigate_sound: AudioStream = preload("res://assets/audio/sfx/monster_finish_investigating.wav")
@export var footstep_max_distance: float = 32.0
@export var patrol_step_interval: float = 0.88          # Tempo langkah santai saat patroli
@export var investigate_step_interval: float = 0.70     # Tempo langkah waspada saat investigasi
@export var chase_step_interval: float = 0.35           # Tempo langkah cepat saat mengejar (chase)

# ==============================================================================
# NODE REFERENCES
# ==============================================================================
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var sprite: Sprite3D = get_node_or_null("Sprite3D")
@onready var model: Node3D = get_node_or_null("Model")
@onready var anim_player: AnimationPlayer = (get_node_or_null("Model/AnimationPlayer") if has_node("Model/AnimationPlayer") else get_node_or_null("AnimationPlayer")) as AnimationPlayer
@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
@onready var scream_player: AudioStreamPlayer3D = get_node_or_null("ScreamPlayer")
@onready var footstep_player: AudioStreamPlayer3D = get_node_or_null("FootstepPlayer")
@onready var voice_player: AudioStreamPlayer3D = get_node_or_null("VoicePlayer")
@onready var jumpscare_light: OmniLight3D = get_node_or_null("JumpscareLight")
@onready var game_over_ui: CanvasLayer = get_node_or_null("GameOverUI")

# ==============================================================================
# RUNTIME STATE
# ==============================================================================
var current_state: State = State.PATROL:
	set(val):
		if current_state != val:
			current_state = val
			state_changed.emit(val)
var chase_source: ChaseSource = ChaseSource.NONE

var spawn_position: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var last_target_position: Vector3 = Vector3.INF
var state_timer: float = 0.0
var direct_chase_timer: float = 0.0
var last_known_player_position: Vector3 = Vector3.ZERO
var stuck_timer: float = 0.0
var footstep_timer: float = 0.0
var footstep_alt: bool = false
var is_waiting: bool = false
var has_screamed_chase: bool = false
var current_waypoint_index: int = -1

var astar_grid: AStarGrid2D = null
var current_path: Array[Vector3] = []
var current_path_index: int = 0

# ==============================================================================
# DEBUG VISUALS & STATE MONITORING
# ==============================================================================
var debug_enabled: bool = false:
	set(val):
		debug_enabled = val
		if debug_mesh_instance:
			debug_mesh_instance.visible = debug_enabled
			if not debug_enabled and debug_immediate_mesh:
				debug_immediate_mesh.clear_surfaces()
		if debug_label_3d:
			debug_label_3d.visible = debug_enabled

var debug_mesh_instance: MeshInstance3D = null
var debug_immediate_mesh: ImmediateMesh = null
var debug_material: StandardMaterial3D = null
var debug_label_3d: Label3D = null
var path_recalc_timer: float = 0.0
var is_permanent_chase: bool = false

var player: Node3D = null

# ==============================================================================
# INITIALIZATION
# ==============================================================================
func _ready() -> void:
	add_to_group("monster")
	spawn_position = global_position

	_init_visuals()
	_init_audio()
	_init_debug_draw()
	_init_default_waypoints()
	_init_navigation_grid()
	_find_player()
	target_position = get_next_patrol_target()
	last_target_position = target_position
	current_path = find_path_to(target_position)
	current_path_index = 0
	if not current_path.is_empty():
		var to_wp := (current_path[0] - global_position)
		to_wp.y = 0.0
		if to_wp.length_squared() > 0.04:
			basis = Basis.looking_at(to_wp.normalized(), Vector3.UP)

	# Pemindaian ulang pada physics frame pertama untuk memastikan semua sibling StaticBody / CSGBox di level sudah siap
	if is_inside_tree() and get_tree():
		get_tree().physics_frame.connect(scan_obstacles, CONNECT_ONE_SHOT)

func _init_visuals() -> void:
	# 1. Inisialisasi Model 3D & Shaders
	if model:
		model.rotation.y = PI
		_apply_model_materials()
		_init_animations()
		if mesh_instance:
			mesh_instance.visible = false
		if sprite:
			sprite.visible = false

	# 2. Fallback / legacy quad mesh
	var tex := load_monster_texture()
	var mat := _setup_visual_material(tex)

	if mesh_instance and model == null:
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

	if sprite and model == null:
		sprite.material_override = mat
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.shaded = true
		sprite.texture = tex
		sprite.position = Vector3(0.0, monster_height * 0.5, 0.0)
		sprite.layers = 1

	_init_jumpscare_light()
	reset_monster_visuals()

func _apply_model_materials() -> void:
	if model == null:
		return
	var body_mat := load("res://assets/material/noir_monster.tres") as Material
	var face_mat := load("res://assets/material/noir_monster_face.tres") as Material
	if body_mat == null or face_mat == null:
		return
	_apply_monster_mats_recursive(model, body_mat, face_mat)

func _apply_monster_mats_recursive(node: Node, body_mat: Material, face_mat: Material) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		mi.material_override = null
		if mi.mesh:
			var surf_count := mi.mesh.get_surface_count()
			for s_idx in range(surf_count):
				if (mi.name == "Plane" and s_idx == 1) or mi.name == "Plane_001":
					mi.set_surface_override_material(s_idx, face_mat)
				else:
					mi.set_surface_override_material(s_idx, body_mat)
	for child in node.get_children():
		_apply_monster_mats_recursive(child, body_mat, face_mat)

func _init_animations() -> void:
	if anim_player == null:
		return
	if anim_player.has_animation("patrol"):
		anim_player.get_animation("patrol").loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation("chase"):
		anim_player.get_animation("chase").loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation("idle"):
		anim_player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation("jumpscare"):
		anim_player.get_animation("jumpscare").loop_mode = Animation.LOOP_NONE
	play_animation("patrol")

func play_animation(anim_name: String, speed: float = 1.0, blend: float = 0.2) -> void:
	if anim_player == null or not anim_player.has_animation(anim_name):
		return
	if anim_player.current_animation == anim_name and anim_player.is_playing():
		anim_player.speed_scale = speed
		return
	anim_player.speed_scale = speed
	anim_player.play(anim_name, blend)

func _init_jumpscare_light() -> void:
	if jumpscare_light == null:
		jumpscare_light = get_node_or_null("JumpscareLight")
	if jumpscare_light == null:
		jumpscare_light = OmniLight3D.new()
		jumpscare_light.name = "JumpscareLight"
		jumpscare_light.position = Vector3(0.0, 1.4, 0.4)
		jumpscare_light.light_energy = 3.5
		jumpscare_light.omni_range = 4.0
		jumpscare_light.visible = false
		add_child(jumpscare_light)

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
		# Hanya isi waypoint bawaan jika berada di grid test_world kecil
		if is_equal_approx(grid_bounds_min.x, -9.6) and is_equal_approx(grid_bounds_max.x, 9.6):
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
		scream_player.unit_size = 10.0
		scream_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		scream_player.panning_strength = 1.0
		add_child(scream_player)
	if scream_player.stream == null and scream_sound != null:
		scream_player.stream = scream_sound

	if footstep_player == null:
		footstep_player = AudioStreamPlayer3D.new()
		footstep_player.name = "FootstepPlayer"
		footstep_player.transform.origin = Vector3(0.0, 0.2, 0.0)
		footstep_player.max_distance = footstep_max_distance
		footstep_player.unit_size = 5.0
		footstep_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		footstep_player.panning_strength = 1.2
		footstep_player.max_polyphony = 2
		footstep_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(footstep_player)
	if footstep_player.stream == null and footstep_sound != null:
		footstep_player.stream = footstep_sound

	if voice_player == null:
		voice_player = get_node_or_null("VoicePlayer")
	if voice_player == null:
		voice_player = AudioStreamPlayer3D.new()
		voice_player.name = "VoicePlayer"
		voice_player.transform.origin = Vector3(0.0, 1.2, 0.0)
		voice_player.max_distance = 32.0
		voice_player.unit_size = 5.5
		voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice_player.panning_strength = 1.2
		voice_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(voice_player)

func play_investigate_sound() -> void:
	if voice_player == null:
		_init_audio()
	if voice_player and investigate_sound:
		voice_player.stream = investigate_sound
		voice_player.volume_db = 1.0
		voice_player.play()

func play_finish_investigate_sound() -> void:
	if voice_player == null:
		_init_audio()
	if voice_player and finish_investigate_sound:
		voice_player.stream = finish_investigate_sound
		voice_player.volume_db = 1.5
		voice_player.play()

func stop_voice_sound() -> void:
	if voice_player and voice_player.playing:
		voice_player.stop()

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
	if player.has_signal("footstep_stepped") and not player.footstep_stepped.is_connected(_on_player_footstep_stepped):
		player.footstep_stepped.connect(_on_player_footstep_stepped)

func _on_player_footstep_stepped(is_sprint: bool) -> void:
	if not is_sprint or not is_instance_valid(player) or current_state == State.JUMPSCARE:
		return
	var player_pos := player.global_position
	var dist := global_position.distance_to(player_pos)
	var sprint_hearing_range: float = 12.0

	if dist <= sprint_hearing_range:
		last_known_player_position = player_pos
		if current_state == State.PATROL:
			print("[MONSTER] Mendengar suara derap lari pemain di jarak %.1fm! Menuju lokasi suara..." % dist)
			investigate_at(player_pos)
		elif current_state == State.CHASE:
			last_target_position = player_pos
			target_position = player_pos

func investigate_at(pos: Vector3) -> void:
	var was_investigating := (current_state == State.INVESTIGATE)
	current_state = State.INVESTIGATE
	chase_source = ChaseSource.NONE
	has_screamed_chase = false
	is_waiting = false
	target_position = pos
	last_target_position = target_position
	current_path = find_path_to(pos)
	current_path_index = 0
	state_timer = 0.0
	if not was_investigating or (voice_player and not voice_player.playing):
		play_investigate_sound()
	emit_signal("investigation_started", pos)

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

	_update_facing_direction(delta)
	_update_footsteps(delta)

	if debug_enabled:
		_update_debug_draw()

func _update_facing_direction(delta: float) -> void:
	if current_state == State.JUMPSCARE:
		if is_instance_valid(player):
			var to_p := (player.global_position - global_position)
			to_p.y = 0.0
			if to_p.length_squared() > 0.01:
				basis = Basis.looking_at(to_p.normalized(), Vector3.UP)
		return

	if current_state == State.CHASE and is_instance_valid(player):
		var to_p := (player.global_position - global_position)
		to_p.y = 0.0
		if to_p.length_squared() > 0.04:
			var target_basis := Basis.looking_at(to_p.normalized(), Vector3.UP)
			basis = basis.slerp(target_basis, clampf(14.0 * delta, 0.0, 1.0))
			return

	var horiz_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horiz_vel.length_squared() > 0.04:
		var target_basis := Basis.looking_at(horiz_vel.normalized(), Vector3.UP)
		basis = basis.slerp(target_basis, clampf(10.0 * delta, 0.0, 1.0))

# ==============================================================================
# PATROL LOGIC
# ==============================================================================
func _update_patrol(delta: float) -> void:
	if target_position != last_target_position or current_path.is_empty():
		last_target_position = target_position
		current_path = find_path_to(target_position)
		current_path_index = 0

	var player_holding: bool = is_instance_valid(player) and "is_holding_breath" in player and player.is_holding_breath
	var dist_to_player: float = global_position.distance_to(player.global_position) if is_instance_valid(player) else 999.0

	# 1. Fase Diam Sebentar (1.0 - 2.0 detik) saat sampai di titik tujuan
	if is_waiting:
		play_animation("idle", 1.0)
		# Jika player sedang menahan napas di dekat (< 5.5m), jangan diam nongkrong: segera lanjut patroli menjauh!
		if player_holding and dist_to_player < 5.5:
			is_waiting = false
			state_timer = 0.0
			target_position = get_next_patrol_target()
			last_target_position = target_position
			current_path = find_path_to(target_position)
			current_path_index = 0
			return

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
			last_target_position = target_position
			current_path = find_path_to(target_position)
			current_path_index = 0
			print("[MONSTER] Jeda patroli selesai. Menuju ke titik patroli baru via A*: ", target_position)
		return

	# Jika saat sedang berjalan patroli, pemain mulai menahan napas dan target patroli monster terlalu dekat ke pemain (< 3.0m):
	# Segera alihkan rute ke target lain yang menjauh dari pemain!
	if player_holding and dist_to_player < 5.5 and is_instance_valid(player) and target_position.distance_to(player.global_position) < 3.0:
		target_position = get_next_patrol_target()
		last_target_position = target_position
		current_path = find_path_to(target_position)
		current_path_index = 0
		return

	# 2. Cek apakah sudah sampai di titik tujuan patroli (jarak horizontal <= 0.85m atau titik akhir rute tercapai)
	var diff := target_position - global_position
	diff.y = 0.0
	var dist := diff.length()
	var path_finished: bool = (not current_path.is_empty() and current_path_index >= current_path.size() - 1 and (current_path[-1] - global_position).length() <= waypoint_reach_dist + 0.15)

	if dist <= 0.85 or path_finished:
		# Jika player sedang menahan napas di dekat, lewati tanpa berhenti diam
		if player_holding and dist_to_player < 5.5:
			is_waiting = false
			stuck_timer = 0.0
			target_position = get_next_patrol_target()
			last_target_position = target_position
			current_path = find_path_to(target_position)
			current_path_index = 0
			print("[MONSTER] Melewati pemain yang sedang menahan napas tanpa berhenti.")
			return

		is_waiting = true
		state_timer = randf_range(patrol_wait_min, patrol_wait_max)
		stuck_timer = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		print("[MONSTER] Sampai di titik tujuan patroli %s. Diam sebentar selama %s detik..." % [target_position, snapped(state_timer, 0.1)])
		return

	# 3. Deteksi tabrakan dinding/objek/macet (Anti-Stuck):
	var horiz_vel := Vector2(velocity.x, velocity.z).length()
	var real_vel := get_real_velocity()
	var real_speed := Vector2(real_vel.x, real_vel.z).length()

	if (is_on_wall() and horiz_vel > 0.2) or (horiz_vel > 0.4 and real_speed < 0.12):
		stuck_timer += delta
		if stuck_timer >= 0.7:
			stuck_timer = 0.0
			# Lepaskan fisik monster jika terjepit di sudut/pojok dinding
			if is_on_wall():
				var wall_n := get_wall_normal()
				wall_n.y = 0.0
				if wall_n.length() > 0.01:
					global_position += wall_n.normalized() * 0.18
			target_position = get_next_patrol_target()
			last_target_position = target_position
			current_path = find_path_to(target_position)
			current_path_index = 0
			print("[MONSTER] Mentok menabrak rintangan! Nudge keluar & mengalihkan ke titik patroli baru: %s" % [target_position])
			return
	else:
		stuck_timer = maxf(0.0, stuck_timer - delta * 0.5)

	# 4. Berjalan aktif mengikuti rute terdekat A* dengan Raycast Smoothing
	play_animation("patrol", clampf(patrol_speed / 1.8, 0.8, 1.6))
	_follow_path(patrol_speed, delta)

func get_next_patrol_target() -> Vector3:
	var player_holding: bool = is_instance_valid(player) and "is_holding_breath" in player and player.is_holding_breath and global_position.distance_to(player.global_position) < 6.0
	var player_pos: Vector3 = player.global_position if is_instance_valid(player) else Vector3.ZERO

	if not patrol_waypoints.is_empty():
		if player_holding:
			# Cari waypoint berikutnya dalam daftar yang mengarah menjauh dari posisi pemain (jarak >= 5.5m)
			for step in range(patrol_waypoints.size()):
				var idx := posmod(current_waypoint_index + 1 + step, patrol_waypoints.size())
				var candidate_wp := patrol_waypoints[idx]
				if candidate_wp.distance_to(player_pos) >= 5.5:
					current_waypoint_index = idx
					candidate_wp.x = clampf(candidate_wp.x, patrol_bounds_min.x, patrol_bounds_max.x)
					candidate_wp.z = clampf(candidate_wp.z, patrol_bounds_min.y, patrol_bounds_max.y)
					candidate_wp.y = global_position.y
					return candidate_wp

		current_waypoint_index = posmod(current_waypoint_index + 1, patrol_waypoints.size())
		var wp := patrol_waypoints[current_waypoint_index]
		wp.x = clampf(wp.x, patrol_bounds_min.x, patrol_bounds_max.x)
		wp.z = clampf(wp.z, patrol_bounds_min.y, patrol_bounds_max.y)
		wp.y = global_position.y
		return wp

	var current_pos_2d := Vector2(global_position.x, global_position.z)
	var player_pos_2d := Vector2(player_pos.x, player_pos.z)
	for i in range(16):
		var rx := randf_range(patrol_bounds_min.x, patrol_bounds_max.x)
		var rz := randf_range(patrol_bounds_min.y, patrol_bounds_max.y)
		var candidate_2d := Vector2(rx, rz)
		if current_pos_2d.distance_to(candidate_2d) >= min_patrol_distance:
			if player_holding and candidate_2d.distance_to(player_pos_2d) < 5.5:
				continue # Jangan pilih titik dekat pemain saat pemain sedang menahan napas!
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
	if target_position != last_target_position or current_path.is_empty():
		last_target_position = target_position
		current_path = find_path_to(target_position)
		current_path_index = 0

	var player_holding: bool = is_instance_valid(player) and "is_holding_breath" in player and player.is_holding_breath
	var dist_to_player: float = global_position.distance_to(player.global_position) if is_instance_valid(player) else 999.0

	# 1. Fase Menunggu Investigasi Selesai
	if is_waiting:
		play_animation("idle", 1.0)
		# Jika pemain sedang menahan napas di dekat (< 5.5m), monster tidak nongkrong: langsung kembali patroli menjauh!
		if player_holding and dist_to_player < 5.5:
			is_waiting = false
			_enter_patrol()
			return

		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = -0.1
		move_and_slide()

		state_timer -= delta
		if state_timer <= 0.0:
			_enter_patrol()
		return

	# 2. Cek apakah sudah sampai di lokasi investigasi atau path selesai
	var diff := target_position - global_position
	diff.y = 0.0
	var dist_to_target := diff.length()
	var path_finished: bool = (not current_path.is_empty() and current_path_index >= current_path.size() - 1 and (current_path[-1] - global_position).length() <= waypoint_reach_dist + 0.15)

	if dist_to_target <= 1.2 or path_finished:
		# Jika pemain sedang menahan napas di dekat: monster menyimpulkan tidak ada siapa-siapa, segera beranjak pergi
		if player_holding and dist_to_player < 5.5:
			print("[MONSTER] Suara ekolokasi hilang, pemain menahan napas. Kembali patroli menjauh.")
			_enter_patrol()
			return

		is_waiting = true
		state_timer = investigate_wait_time
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# 3. Deteksi Mentok (Anti-Stuck) saat investigasi
	var horiz_vel := Vector2(velocity.x, velocity.z).length()
	var real_vel := get_real_velocity()
	var real_speed := Vector2(real_vel.x, real_vel.z).length()

	if (is_on_wall() and horiz_vel > 0.2) or (horiz_vel > 0.4 and real_speed < 0.12):
		stuck_timer += delta
		if stuck_timer >= 0.7:
			stuck_timer = 0.0
			if is_on_wall():
				var wall_n := get_wall_normal()
				wall_n.y = 0.0
				if wall_n.length() > 0.01:
					global_position += wall_n.normalized() * 0.18
			print("[MONSTER] Terhalang rintangan saat investigasi. Nudge keluar & kembali ke Patroli.")
			_enter_patrol()
			return
	else:
		stuck_timer = maxf(0.0, stuck_timer - delta * 0.5)

	# 4. Berjalan aktif mengikuti rute
	play_animation("patrol", clampf(investigate_speed / 1.8, 0.8, 1.6))
	_follow_path(investigate_speed, delta)

func _on_echolocation_made(sound_origin: Vector3, _radius: float) -> void:
	if current_state == State.CHASE or current_state == State.JUMPSCARE:
		return

	var dist := global_position.distance_to(sound_origin)
	if dist <= hearing_radius:
		var was_investigating := (current_state == State.INVESTIGATE)
		current_state = State.INVESTIGATE
		target_position = sound_origin
		last_target_position = target_position
		current_path = find_path_to(sound_origin)
		current_path_index = 0
		is_waiting = false
		state_timer = 0.0
		# Putar audio investigasi jika belum berbunyi
		if not was_investigating or (voice_player and not voice_player.playing):
			play_investigate_sound()
		emit_signal("investigation_started", sound_origin)
		print("[MONSTER] Mendengar suara ekolokasi di %s (jarak: %s m). Menuju lokasi via A* Shortest Path..." % [sound_origin, snapped(dist, 0.1)])

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

	# Catat posisi pemain setiap frame
	last_known_player_position = player_pos

	# Cek apakah monster masih memiliki Line of Sight langsung ke pemain
	var has_los := _has_line_of_sight(player_pos)

	if is_permanent_chase:
		# Mode Klimaks Pintu Terbuka: Monster tidak pernah menyerah atau kembali ke patroli!
		pass
	elif chase_source == ChaseSource.DIRECT_SHINE:
		if has_los:
			# Selama pemain masih terlihat langsung (misal di lorong panjang):
			# Reset timer kejaran agar monster TIDAK PERNAH berhenti mengejar di depan mata pemain!
			direct_chase_timer = direct_trigger_chase_duration
		else:
			# Garis pandang terputus (pemain berbelok atau masuk kamar):
			# Timer hitung mundur mulai berjalan!
			direct_chase_timer -= delta
			if direct_chase_timer <= 0.0:
				print("[MONSTER] Kehilangan garis pandang pemain di balik belokan. Menuju ke lokasi terakhir terlihat untuk mencari!")
				_enter_search_at_last_known()
				return
	elif chase_source == ChaseSource.OVERHEAT:
		var is_player_triggered: bool = false
		if "is_triggered" in player:
			is_player_triggered = player.is_triggered
		if not is_player_triggered and not has_los:
			print("[MONSTER] Masa kejaran Overheat selesai & pemain tidak terlihat. Menuju lokasi terakhir untuk mencari.")
			_enter_search_at_last_known()
			return

	# Update rute A* secara berkala ke posisi real-time player
	path_recalc_timer -= delta
	if path_recalc_timer <= 0.0 or current_path.is_empty() or last_target_position.distance_to(player_pos) > 1.2:
		path_recalc_timer = chase_recalc_interval
		target_position = player_pos
		last_target_position = target_position
		current_path = find_path_to(player_pos)
		current_path_index = 0

	# Anti-stuck saat mengejar jika terjepit di sudut/pojok dinding
	var horiz_vel := Vector2(velocity.x, velocity.z).length()
	var real_vel := get_real_velocity()
	var real_speed := Vector2(real_vel.x, real_vel.z).length()
	if is_on_wall() or (horiz_vel > 0.5 and real_speed < 0.12):
		stuck_timer += delta
		if stuck_timer >= 0.7:
			stuck_timer = 0.0
			if is_on_wall():
				var wall_n := get_wall_normal()
				wall_n.y = 0.0
				if wall_n.length() > 0.01:
					global_position += wall_n.normalized() * 0.18
			path_recalc_timer = 0.0
			current_path = find_path_to(player_pos)
			current_path_index = 0
	else:
		stuck_timer = maxf(0.0, stuck_timer - delta * 0.5)

	play_animation("chase", clampf(chase_speed / 3.6, 0.9, 1.8))
	_follow_path(chase_speed, delta)

func _enter_search_at_last_known() -> void:
	investigate_at(last_known_player_position)
	print("[MONSTER] Beralih ke INVESTIGASI / SEARCH di lokasi terakhir pemain terlihat: %s" % last_known_player_position)

func trigger_direct_shine_chase() -> void:
	current_state = State.CHASE
	chase_source = ChaseSource.DIRECT_SHINE
	direct_chase_timer = direct_trigger_chase_duration
	is_waiting = false
	path_recalc_timer = 0.0 # Segera hitung jalur ke posisi player
	print("[MONSTER] CHASE AKTIF: Monster tersorot senter langsung (Kondisi B)! Durasi kejar: %s detik." % direct_trigger_chase_duration)
	_play_scream()
	play_animation("chase", clampf(chase_speed / 3.6, 0.9, 1.8))

func _on_player_flashlight_overheated(_player_pos: Vector3) -> void:
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
	path_recalc_timer = 0.0
	print("[MONSTER] CHASE AKTIF: Parameter senter overheat 100% (Kondisi A)!")
	if not has_screamed_chase:
		_play_scream()
		has_screamed_chase = true
	play_animation("chase", clampf(chase_speed / 3.6, 0.9, 1.8))

func trigger_permanent_chase() -> void:
	is_permanent_chase = true
	current_state = State.CHASE
	chase_source = ChaseSource.OVERHEAT
	is_waiting = false
	path_recalc_timer = 0.0
	_play_scream()
	play_animation("chase", clampf(chase_speed / 3.6, 0.9, 1.8))
	print("[MONSTER] KLIMAKS CHASE PERMANEN AKTIF: Pintu keluar terbuka!")

func trigger_close_gasp_chase() -> void:
	if current_state == State.JUMPSCARE:
		return
	current_state = State.CHASE
	chase_source = ChaseSource.DIRECT_SHINE
	direct_chase_timer = direct_trigger_chase_duration
	is_waiting = false
	path_recalc_timer = 0.0
	print("[MONSTER] CHASE AKTIF: Mendengar nafas ngos-ngosan / gasping pemain dari jarak dekat (<6m)!")
	_play_scream()
	play_animation("chase", clampf(chase_speed / 3.6, 0.9, 1.8))

func trigger_lethal_hearing_chase() -> void:
	if current_state == State.JUMPSCARE or current_state == State.CHASE:
		return
	current_state = State.CHASE
	chase_source = ChaseSource.DIRECT_SHINE
	direct_chase_timer = direct_trigger_chase_duration
	is_waiting = false
	path_recalc_timer = 0.0
	print("[MONSTER] CHASE AKTIF: Mendeteksi suara/cahaya pemain di Lethal Hearing Zone (<4m)!")
	_play_scream()
	play_animation("chase", clampf(chase_speed / 3.6, 0.9, 1.8))

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
	play_animation("jumpscare", 1.0, 0.0)

	# 1. Posisikan wajah monster tepat di depan kamera player (jarak 0.6m - 1.0m, anti-clipping & anti-obstruct)
	_position_for_jumpscare()

	# 2. Paksa visual monster langsung terlihat jelas di kegelapan:
	#    - Ubah material secara dinamis: SHADING_MODE_UNSHADED + emission terang
	#    - Nyalakan cahaya sorot jumpscare (OmniLight3D)
	_apply_jumpscare_visuals()

	# 3. Kunci pergerakan player dan picu animasi/camera shake jumpscare
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

func _position_for_jumpscare() -> void:
	if not is_instance_valid(player):
		return

	var cam: Camera3D = null
	if "camera" in player and player.camera is Camera3D:
		cam = player.camera
	elif player.has_node("Head/Camera3D"):
		cam = player.get_node("Head/Camera3D") as Camera3D

	var cam_pos := cam.global_position if cam else (player.global_position + Vector3(0.0, 1.6, 0.0))
	var jumpscare_dist: float = 1.85 # Animasi jumpscare menerjang maju ~1.1m sehingga wajah berhenti di jarak ~0.75m (anti-clipping)

	# Arah horizontal dari kamera ke monster (atau arah pandang kamera)
	var forward := -cam.global_transform.basis.z if cam else -player.global_transform.basis.z
	var dir_to_monster := global_position - player.global_position
	dir_to_monster.y = 0.0

	var target_dir := Vector3.ZERO
	if dir_to_monster.length() > 0.1:
		target_dir = dir_to_monster.normalized()
	else:
		target_dir = Vector3(forward.x, 0.0, forward.z).normalized()
		if target_dir.length() < 0.01:
			target_dir = Vector3(0.0, 0.0, -1.0)

	var target_pos := cam_pos + target_dir * jumpscare_dist
	target_pos.y = player.global_position.y

	# Anti-Obstruction Check: Raycast dari kamera ke target_pos agar tidak tertutup tembok/objek
	if is_inside_tree() and get_world_3d():
		var space_state := get_world_3d().direct_space_state
		if space_state:
			var query := PhysicsRayQueryParameters3D.create(cam_pos, target_pos + Vector3(0.0, 1.8, 0.0))
			var excludes: Array[RID] = [get_rid()]
			if player is CollisionObject3D:
				excludes.append(player.get_rid())
			query.exclude = excludes
			var hit := space_state.intersect_ray(query)
			if not hit.is_empty():
				var hit_pos: Vector3 = hit.position
				var hit_dir := (hit_pos - cam_pos).normalized()
				var safe_dist := maxf(1.1, hit_pos.distance_to(cam_pos) - 0.2)
				target_pos = cam_pos + hit_dir * safe_dist
				target_pos.y = player.global_position.y

	global_position = target_pos
	if is_instance_valid(player):
		var to_player := (player.global_position - global_position)
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			basis = Basis.looking_at(to_player.normalized(), Vector3.UP)

func _apply_jumpscare_visuals() -> void:
	# 1. Ubah material secara dinamis: Unshaded + Emission terang jika ada
	var mat: StandardMaterial3D = _get_active_material()
	if mat:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(1.0, 1.0, 1.0, 1.0)
		mat.emission_energy_multiplier = 1.2
		mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)

	# 2. Nyalakan lampu sorot khusus jumpscare di depan wajah
	if jumpscare_light:
		jumpscare_light.visible = true
		jumpscare_light.light_energy = 1.2
		jumpscare_light.position = Vector3(0.0, 2.2, 0.4)

	# 3. Nyalakan juga cahaya di player (flashlight) jika ada agar wajah monster tersinari langsung
	if is_instance_valid(player) and "flashlight" in player and player.flashlight is SpotLight3D:
		player.flashlight.visible = true
		player.flashlight.light_energy = maxf(player.flashlight.light_energy, 1.5)

func reset_monster_visuals() -> void:
	# Kembalikan material ke mode gameplay normal (100% hitam pekat dalam kegelapan)
	var mat: StandardMaterial3D = _get_active_material()
	if mat:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.emission_enabled = false
		mat.emission = Color.BLACK
		mat.emission_energy_multiplier = 0.0
		mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)

	if jumpscare_light:
		jumpscare_light.visible = false
		jumpscare_light.light_energy = 0.0

	if footstep_player and footstep_player.playing:
		footstep_player.stop()
	footstep_timer = 0.0

func _get_active_material() -> StandardMaterial3D:
	if mesh_instance and mesh_instance.material_override is StandardMaterial3D:
		return mesh_instance.material_override as StandardMaterial3D
	if sprite and sprite.material_override is StandardMaterial3D:
		return sprite.material_override as StandardMaterial3D
	return null

# ==============================================================================
# LOCOMOTION, A* NAVIGATION & RAYCAST SMOOTHING
# ==============================================================================
func _init_navigation_grid() -> void:
	astar_grid = AStarGrid2D.new()
	var w := int(round((grid_bounds_max.x - grid_bounds_min.x) / grid_cell_size))
	var h := int(round((grid_bounds_max.y - grid_bounds_min.y) / grid_cell_size))
	astar_grid.region = Rect2i(0, 0, w, h)
	astar_grid.cell_size = Vector2(grid_cell_size, grid_cell_size)
	astar_grid.offset = Vector2(grid_bounds_min.x + grid_cell_size * 0.5, grid_bounds_min.y + grid_cell_size * 0.5)
	astar_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar_grid.update()

	scan_obstacles()

func scan_obstacles() -> void:
	if astar_grid == null or not is_inside_tree():
		return

	var world_3d := get_world_3d()
	if world_3d == null:
		return
	var space_state := world_3d.direct_space_state
	if space_state == null:
		return

	var r := astar_grid.region
	var shape := SphereShape3D.new()
	shape.radius = obstacle_margin_radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excludes: Array[RID] = [get_rid()]
	if is_instance_valid(player) and player is CollisionObject3D:
		excludes.append(player.get_rid())
	query.exclude = excludes

	var solid_count := 0
	var y_scan := global_position.y + scan_height

	for gx in range(r.size.x):
		for gz in range(r.size.y):
			var pos_2d := astar_grid.get_point_position(Vector2i(gx, gz))
			var check_pos := Vector3(pos_2d.x, y_scan, pos_2d.y)
			query.transform = Transform3D(Basis(), check_pos)
			var hits = space_state.intersect_shape(query, 1)
			if not hits.is_empty():
				var collider = hits[0].collider
				# Jangan tandai lantai horizontal sebagai obstacle
				if collider is CSGBox3D and collider.name == "CSGBox3D":
					continue
				if collider.name in ["Plane", "Lantai", "Atap"] or (collider.get_parent() and (collider.get_parent().name.begins_with("Plane") or collider.get_parent().name in ["Lantai", "Atap"])):
					continue
				astar_grid.set_point_solid(Vector2i(gx, gz), true)
				solid_count += 1

	print("[MONSTER] Auto-Scan AStarGrid2D selesai. Grid: %dx%d (%d sel), Solid obstacle: %d sel." % [r.size.x, r.size.y, r.size.x * r.size.y, solid_count])

func world_to_grid(world_pos: Vector3) -> Vector2i:
	if astar_grid == null:
		return Vector2i.ZERO
	var gx := int(floor((world_pos.x - grid_bounds_min.x) / grid_cell_size))
	var gz := int(floor((world_pos.z - grid_bounds_min.y) / grid_cell_size))
	var r := astar_grid.region
	return Vector2i(clampi(gx, 0, r.size.x - 1), clampi(gz, 0, r.size.y - 1))

func grid_to_world(grid_pos: Vector2i, y_pos: float = 0.0) -> Vector3:
	if astar_grid == null:
		return Vector3(grid_pos.x, y_pos, grid_pos.y)
	var pos_2d := astar_grid.get_point_position(grid_pos)
	return Vector3(pos_2d.x, y_pos, pos_2d.y)

func find_nearest_walkable_cell(cell: Vector2i, max_radius: int = 6) -> Vector2i:
	if astar_grid == null:
		return cell
	if astar_grid.is_in_boundsv(cell) and not astar_grid.is_point_solid(cell):
		return cell
	for r in range(1, max_radius + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var check := cell + Vector2i(dx, dy)
				if astar_grid.is_in_boundsv(check) and not astar_grid.is_point_solid(check):
					return check
	return cell

func find_path_to(target_pos: Vector3) -> Array[Vector3]:
	var result_path: Array[Vector3] = []
	var y_lvl := global_position.y

	if astar_grid == null:
		result_path.append(Vector3(target_pos.x, y_lvl, target_pos.z))
		return result_path

	var start_cell := world_to_grid(global_position)
	var end_cell := world_to_grid(target_pos)

	start_cell = find_nearest_walkable_cell(start_cell)
	end_cell = find_nearest_walkable_cell(end_cell)

	var pts_2d := astar_grid.get_point_path(start_cell, end_cell, true)
	if pts_2d.is_empty():
		result_path.append(Vector3(target_pos.x, y_lvl, target_pos.z))
		return result_path

	for p in pts_2d:
		result_path.append(Vector3(p.x, y_lvl, p.y))

	# Jika titik terakhir path agak jauh dari target akhir yang diminta, tambahkan target_pos
	if not result_path.is_empty():
		var last_pt := result_path[-1]
		if Vector2(last_pt.x, last_pt.z).distance_to(Vector2(target_pos.x, target_pos.z)) > 0.15:
			result_path.append(Vector3(target_pos.x, y_lvl, target_pos.z))

	return result_path

func _follow_path(speed: float, delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	if current_path.is_empty():
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	# Majukan waypoint jika monster sudah mendekati titik waypoint saat ini
	while current_path_index < current_path.size() - 1:
		var wp := current_path[current_path_index]
		var diff_wp := wp - global_position
		diff_wp.y = 0.0
		if diff_wp.length() < waypoint_reach_dist:
			current_path_index += 1
		else:
			# Line-of-sight shortcutting:
			# Hanya boleh potong rute jika:
			# 1. Monster tidak sedang menempel/menyentuh dinding (not is_on_wall())
			# 2. Sudut ke waypoint berikutnya bukan tikungan tajam / sudut pojok (angle < 35 derajat)
			# 3. Seluruh lebar badan monster (shoulder clearance) memiliki garis pandang bebas rintangan
			if not is_on_wall() and current_path_index + 1 < current_path.size():
				var next_wp := current_path[current_path_index + 1]
				var dir_to_wp := diff_wp.normalized()
				var dir_next := (next_wp - wp)
				dir_next.y = 0.0
				# Jika berbelok tajam di sudut (> 35 derajat, dot < 0.82), monster WAJIB mengitari puncak sudut waypoint terlebih dahulu
				if dir_next.length() > 0.05 and dir_to_wp.dot(dir_next.normalized()) < 0.82:
					break
				if _has_line_of_sight(next_wp):
					current_path_index += 1
			break

	var current_target_pt := current_path[current_path_index]
	var diff := current_target_pt - global_position
	diff.y = 0.0
	var dist := diff.length()

	if dist > 0.05:
		var desired_dir := diff.normalized()

		# Raycast Smoothing & Local Avoidance di sekitar sudut/pojok objek
		desired_dir = _apply_raycast_smoothing(desired_dir)

		# Slide collision handling fisik saat menyentuh dinding / objek
		if is_on_wall():
			var wall_norm := get_wall_normal()
			wall_norm.y = 0.0
			if wall_norm.length() > 0.01:
				var norm := wall_norm.normalized()
				# Jika arah gerakan monster mengarah menembus/menekan dinding, pantulkan sedikit menjauh dari dinding
				if desired_dir.dot(norm) < 0.0:
					desired_dir = (desired_dir + norm * 0.6).normalized()

		velocity.x = move_toward(velocity.x, desired_dir.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, desired_dir.z * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)

	move_and_slide()

func _apply_raycast_smoothing(desired_dir: Vector3) -> Vector3:
	if not is_inside_tree():
		return desired_dir
	var world_3d := get_world_3d()
	if world_3d == null:
		return desired_dir
	var space_state := world_3d.direct_space_state
	if space_state == null:
		return desired_dir

	var origin := global_position + Vector3(0.0, scan_height, 0.0)
	var query := PhysicsRayQueryParameters3D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excludes: Array[RID] = [get_rid()]
	if is_instance_valid(player) and player is CollisionObject3D:
		excludes.append(player.get_rid())
	query.exclude = excludes

	var rad := deg_to_rad(avoidance_ray_angle)
	var dir_center := desired_dir
	var dir_left := desired_dir.rotated(Vector3.UP, rad)
	var dir_right := desired_dir.rotated(Vector3.UP, -rad)

	# 1. Center Ray
	query.from = origin
	query.to = origin + dir_center * avoidance_ray_length
	var hit_center := space_state.intersect_ray(query)

	# 2. Left Ray
	query.to = origin + dir_left * (avoidance_ray_length * 0.85)
	var hit_left := space_state.intersect_ray(query)

	# 3. Right Ray
	query.to = origin + dir_right * (avoidance_ray_length * 0.85)
	var hit_right := space_state.intersect_ray(query)

	var steered_dir := desired_dir

	if not hit_center.is_empty():
		var norm: Vector3 = hit_center.normal
		norm.y = 0.0
		if norm.length() > 0.01:
			steered_dir = (steered_dir + norm.normalized() * 0.5).normalized()

	if not hit_left.is_empty():
		var norm: Vector3 = hit_left.normal
		norm.y = 0.0
		steered_dir = (steered_dir + norm.normalized() * 0.45).normalized()

	if not hit_right.is_empty():
		var norm: Vector3 = hit_right.normal
		norm.y = 0.0
		steered_dir = (steered_dir + norm.normalized() * 0.45).normalized()

	return steered_dir if steered_dir.length() > 0.01 else desired_dir

func _has_line_of_sight(to_pos: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var world_3d := get_world_3d()
	if world_3d == null:
		return false
	var space_state := world_3d.direct_space_state
	if space_state == null:
		return false

	var from_pos := global_position + Vector3(0.0, scan_height, 0.0)
	var target_pos := Vector3(to_pos.x, from_pos.y, to_pos.z)
	var diff := target_pos - from_pos
	if diff.length_squared() < 0.001:
		return true

	var excludes: Array[RID] = [get_rid()]
	if is_instance_valid(player) and player is CollisionObject3D:
		excludes.append(player.get_rid())

	# 1. Center Ray
	var query := PhysicsRayQueryParameters3D.create(from_pos, target_pos)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = excludes
	if not space_state.intersect_ray(query).is_empty():
		return false

	# 2. Dual Shoulder Rays (memastikan lebar badan 0.38m di kiri & kanan tidak menabrak sudut dinding)
	var perp := diff.cross(Vector3.UP).normalized() * 0.38
	query.from = from_pos + perp
	query.to = target_pos + perp
	if not space_state.intersect_ray(query).is_empty():
		return false

	query.from = from_pos - perp
	query.to = target_pos - perp
	if not space_state.intersect_ray(query).is_empty():
		return false

	return true

func _move_towards(target: Vector3, speed: float, delta: float) -> void:
	if current_path.is_empty() or target_position != target:
		target_position = target
		last_target_position = target
		current_path = find_path_to(target)
		current_path_index = 0
	_follow_path(speed, delta)

func _enter_patrol() -> void:
	if current_state == State.INVESTIGATE:
		play_finish_investigate_sound()
		emit_signal("investigation_ended")
	current_state = State.PATROL
	chase_source = ChaseSource.NONE
	has_screamed_chase = false
	is_waiting = false
	stuck_timer = 0.0
	reset_monster_visuals()
	play_animation("patrol", clampf(patrol_speed / 1.8, 0.8, 1.6))
	target_position = get_next_patrol_target()
	last_target_position = target_position
	current_path = find_path_to(target_position)
	current_path_index = 0
	if not current_path.is_empty():
		var to_wp := (current_path[0] - global_position)
		to_wp.y = 0.0
		if to_wp.length_squared() > 0.04:
			basis = Basis.looking_at(to_wp.normalized(), Vector3.UP)

func _play_scream() -> void:
	stop_voice_sound()
	if scream_player:
		if scream_player.stream == null and scream_sound != null:
			scream_player.stream = scream_sound
		if scream_player.stream and not scream_player.playing:
			scream_player.pitch_scale = randf_range(0.94, 1.06)
			scream_player.play()

func _update_footsteps(delta: float) -> void:
	if not footstep_player:
		return

	# Jangan bersuara jika sedang jumpscare atau sedang berhenti diam (waiting)
	if current_state == State.JUMPSCARE or is_waiting:
		if footstep_player.playing:
			footstep_player.stop()
		footstep_timer = 0.15
		return

	# Cek apakah monster benar-benar bergerak di atas lantai
	var horiz_vel := Vector2(velocity.x, velocity.z).length()
	var real_vel := get_real_velocity()
	var real_speed := Vector2(real_vel.x, real_vel.z).length()

	if not is_on_floor() or horiz_vel < 0.2 or real_speed < 0.1:
		footstep_timer = 0.15
		return

	# Atur tempo langkah, pitch, dan volume berdasarkan status gerakan monster
	var step_interval: float = patrol_step_interval
	var pitch_min: float = 0.88
	var pitch_max: float = 0.98
	var vol_db: float = -2.0

	match current_state:
		State.CHASE:
			step_interval = chase_step_interval
			pitch_min = 1.15
			pitch_max = 1.25
			vol_db = 5.0
		State.INVESTIGATE:
			step_interval = investigate_step_interval
			pitch_min = 0.96
			pitch_max = 1.05
			vol_db = 2.0
		State.PATROL:
			step_interval = patrol_step_interval
			pitch_min = 0.88
			pitch_max = 0.98
			vol_db = 2.5

	footstep_timer -= delta
	if footstep_timer <= 0.0:
		footstep_timer = step_interval
		_trigger_monster_footstep(pitch_min, pitch_max, vol_db)

func _trigger_monster_footstep(pitch_min: float, pitch_max: float, vol_db: float) -> void:
	if not footstep_player or not footstep_player.is_inside_tree():
		return
	if footstep_player.stream == null and footstep_sound != null:
		footstep_player.stream = footstep_sound
	if footstep_player.stream == null:
		return

	footstep_player.volume_db = vol_db
	footstep_player.pitch_scale = randf_range(pitch_min, pitch_max)

	# Bergantian antara langkah kaki kiri (offset 0.0s) dan kanan (offset 2.38s)
	footstep_alt = not footstep_alt
	var offset: float = 0.0 if footstep_alt else 2.38
	footstep_player.play(offset)

# ==============================================================================
# DEBUG VISUAL DRAWING (WIREFRAME, X-RAY BOUNDING BOX, LINE OF SIGHT, ASTAR PATH)
# ==============================================================================
func _init_debug_draw() -> void:
	debug_immediate_mesh = ImmediateMesh.new()
	debug_material = StandardMaterial3D.new()
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_material.vertex_color_use_as_albedo = true
	debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_material.no_depth_test = true # X-Ray: Tembus pandang dinding tanpa terhalang geometri lain
	debug_material.render_priority = 127 # Prioritas render tertinggi, digambar paling akhir di atas semua pass
	debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.name = "MonsterDebugDraw3D"
	debug_mesh_instance.mesh = debug_immediate_mesh
	debug_mesh_instance.material_override = debug_material
	debug_mesh_instance.top_level = true
	debug_mesh_instance.extra_cull_margin = 16384.0 # Mencegah culling kamera saat pemain berpaling
	debug_mesh_instance.ignore_occlusion_culling = true
	debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	debug_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	debug_mesh_instance.visible = debug_enabled
	add_child(debug_mesh_instance)

	# Label 3D X-Ray Melayang di Atas Kepala Monster
	debug_label_3d = Label3D.new()
	debug_label_3d.name = "MonsterDebugLabel3D"
	debug_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label_3d.no_depth_test = true # X-Ray text tembus dinding
	debug_label_3d.render_priority = 127
	debug_label_3d.pixel_size = 0.006
	debug_label_3d.font = load("res://assets/fonts/HandymandiFree.ttf")
	debug_label_3d.font_size = 28
	debug_label_3d.outline_render_priority = 126
	debug_label_3d.outline_size = 6
	debug_label_3d.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	debug_label_3d.modulate = Color(1.0, 1.0, 1.0, 1.0)
	debug_label_3d.position = Vector3(0.0, monster_height + 0.35, 0.0)
	debug_label_3d.visible = debug_enabled
	add_child(debug_label_3d)

func _update_debug_draw() -> void:
	if not debug_enabled or debug_immediate_mesh == null or not is_inside_tree():
		return

	# State AI dalam teks (Monokrom / Putih)
	var s_text := "PATROL"
	if current_state == State.INVESTIGATE:
		s_text = "INVESTIGATE"
	elif current_state == State.CHASE:
		s_text = "CHASE"
	elif current_state == State.JUMPSCARE:
		s_text = "JUMPSCARE"

	# Update Label 3D X-Ray Melayang (Putih)
	if debug_label_3d:
		var dist_to_p := global_position.distance_to(player.global_position) if (player and is_instance_valid(player)) else 0.0
		debug_label_3d.text = "[MONSTER: %s]\n%.1f m" % [s_text, dist_to_p]
		debug_label_3d.modulate = Color(1.0, 1.0, 1.0, 1.0)

	debug_immediate_mesh.clear_surfaces()

	var center := global_position + Vector3(0.0, monster_height * 0.5, 0.0)
	var hw := monster_width * 0.55
	var hh := monster_height * 0.5
	var hd := monster_width * 0.55

	var p0 := center + Vector3(-hw, -hh, -hd)
	var p1 := center + Vector3( hw, -hh, -hd)
	var p2 := center + Vector3( hw, -hh,  hd)
	var p3 := center + Vector3(-hw, -hh,  hd)
	var p4 := center + Vector3(-hw,  hh, -hd)
	var p5 := center + Vector3( hw,  hh, -hd)
	var p6 := center + Vector3( hw,  hh,  hd)
	var p7 := center + Vector3(-hw,  hh,  hd)

	# 1. Surface Triangles: Solid Translucent X-Ray Box Volume (Putih Transparan)
	debug_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, debug_material)
	var fill_col := Color(1.0, 1.0, 1.0, 0.15)
	_add_debug_quad_triangles(p0, p1, p2, p3, fill_col) # Bawah
	_add_debug_quad_triangles(p4, p5, p6, p7, fill_col) # Atas
	_add_debug_quad_triangles(p3, p2, p6, p7, fill_col) # Depan (+Z)
	_add_debug_quad_triangles(p1, p0, p4, p5, fill_col) # Belakang (-Z)
	_add_debug_quad_triangles(p0, p3, p7, p4, fill_col) # Kiri (-X)
	_add_debug_quad_triangles(p2, p1, p5, p6, fill_col) # Kanan (+X)
	debug_immediate_mesh.surface_end()

	# 2. Surface Lines: Wireframe Edges, Diagonals, Spine, Gaze, and A* Path (Monokrom Putih)
	debug_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, debug_material)
	var wire_col := Color(1.0, 1.0, 1.0, 0.9)

	# 12 Tepi Bounding Box
	_add_debug_segment(p0, p1, wire_col)
	_add_debug_segment(p1, p2, wire_col)
	_add_debug_segment(p2, p3, wire_col)
	_add_debug_segment(p3, p0, wire_col)
	_add_debug_segment(p4, p5, wire_col)
	_add_debug_segment(p5, p6, wire_col)
	_add_debug_segment(p6, p7, wire_col)
	_add_debug_segment(p7, p4, wire_col)
	_add_debug_segment(p0, p4, wire_col)
	_add_debug_segment(p1, p5, wire_col)
	_add_debug_segment(p2, p6, wire_col)
	_add_debug_segment(p3, p7, wire_col)

	# Diagonal X pada Atas dan Bawah Box
	_add_debug_segment(p4, p6, Color(1.0, 1.0, 1.0, 0.5))
	_add_debug_segment(p5, p7, Color(1.0, 1.0, 1.0, 0.5))
	_add_debug_segment(p0, p2, Color(1.0, 1.0, 1.0, 0.4))
	_add_debug_segment(p1, p3, Color(1.0, 1.0, 1.0, 0.4))

	# Tulang vertikal pusat (Center Spine)
	_add_debug_segment(center - Vector3(0, hh, 0), center + Vector3(0, hh, 0), Color(1.0, 1.0, 1.0, 0.6))

	# Garis Pandangan & Cone Penglihatan (Line of Sight)
	var eye_pos := global_position + Vector3(0.0, scan_height, 0.0)
	var fwd := -transform.basis.z.normalized()
	if velocity.length_squared() > 0.05:
		fwd = Vector3(velocity.x, 0.0, velocity.z).normalized()

	# Gaze center line (Putih terang)
	_add_debug_segment(eye_pos, eye_pos + fwd * 4.5, Color(1.0, 1.0, 1.0, 0.9))
	# Vision cone borders (+- 30 derajat)
	var left_cone := fwd.rotated(Vector3.UP, deg_to_rad(30.0))
	var right_cone := fwd.rotated(Vector3.UP, deg_to_rad(-30.0))
	_add_debug_segment(eye_pos, eye_pos + left_cone * 5.0, Color(1.0, 1.0, 1.0, 0.45))
	_add_debug_segment(eye_pos, eye_pos + right_cone * 5.0, Color(1.0, 1.0, 1.0, 0.45))
	_add_debug_segment(eye_pos + left_cone * 5.0, eye_pos + right_cone * 5.0, Color(1.0, 1.0, 1.0, 0.45))

	# Ray ke Player (Putih pekat jika terlihat, putih tipis jika terhalang dinding)
	if player and is_instance_valid(player):
		var p_pos := player.global_position + Vector3(0.0, 1.5, 0.0)
		var has_los := _has_line_of_sight(player.global_position)
		if has_los:
			_add_debug_segment(eye_pos, p_pos, Color(1.0, 1.0, 1.0, 1.0)) # LOS CLEAR
		else:
			_add_debug_segment(eye_pos, p_pos, Color(1.0, 1.0, 1.0, 0.3)) # LOS BLOCKED

	# Garis Jalur Navigasi A* & Target
	var start_path := global_position + Vector3(0.0, 0.08, 0.0)
	for i in range(current_path_index, current_path.size()):
		var target_pt := current_path[i] + Vector3(0.0, 0.08, 0.0)
		_add_debug_segment(start_path, target_pt, Color(1.0, 1.0, 1.0, 0.7))
		start_path = target_pt

	# Marker silang di target tujuan
	var tp := target_position + Vector3(0.0, 0.1, 0.0)
	var ms := 0.45
	_add_debug_segment(tp + Vector3(-ms, 0, 0), tp + Vector3(ms, 0, 0), Color(1.0, 1.0, 1.0, 0.85))
	_add_debug_segment(tp + Vector3(0, 0, -ms), tp + Vector3(0, 0, ms), Color(1.0, 1.0, 1.0, 0.85))
	_add_debug_segment(tp, tp + Vector3(0, 1.2, 0), Color(1.0, 1.0, 1.0, 0.85))

	debug_immediate_mesh.surface_end()

func _add_debug_segment(from: Vector3, to: Vector3, col: Color) -> void:
	debug_immediate_mesh.surface_set_color(col)
	debug_immediate_mesh.surface_add_vertex(from)
	debug_immediate_mesh.surface_set_color(col)
	debug_immediate_mesh.surface_add_vertex(to)

func _add_debug_quad_triangles(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	debug_immediate_mesh.surface_set_color(col)
	debug_immediate_mesh.surface_add_vertex(a)
	debug_immediate_mesh.surface_set_color(col)
	debug_immediate_mesh.surface_add_vertex(b)
	debug_immediate_mesh.surface_set_color(col)
	debug_immediate_mesh.surface_add_vertex(c)

	debug_immediate_mesh.surface_set_color(col)
	debug_immediate_mesh.surface_add_vertex(a)
	debug_immediate_mesh.surface_set_color(col)
	debug_immediate_mesh.surface_add_vertex(c)
	debug_immediate_mesh.surface_set_color(col)
	debug_immediate_mesh.surface_add_vertex(d)
