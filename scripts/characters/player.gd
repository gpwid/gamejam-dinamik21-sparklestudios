extends CharacterBody3D

# ==============================================================================
# SIKAP GERAK & FISIKA (LOCOMOTION)
# ==============================================================================
const WALK_SPEED: float = 3.0
const SPRINT_SPEED: float = 6.0
const ACCELERATION: float = 25.0
const DECELERATION: float = 25.0
const AIR_CONTROL_FACTOR: float = 0.25 # Reduksi kontrol udara saat melayang
const MOUSE_SENSITIVITY: float = 0.003

# ==============================================================================
# KAMERA & IMERSI FISIK TINGKAT LANJUT
# ==============================================================================
# 1. Asymmetric Head Bobbing (Kurva Hentakan Tumit abs(sin))
const BOB_FREQUENCY_WALK: float = 10.0
const BOB_FREQUENCY_SPRINT: float = 14.0
const BOB_AMPLITUDE_WALK: float = 0.05
const BOB_AMPLITUDE_SPRINT: float = 0.08
const BOB_RESET_SPEED: float = 10.0

# 2. Idle Breathing
const BREATH_FREQUENCY: float = 0.35 # Frekuensi pernapasan 0.35 Hz
const BREATH_AMPLITUDE_Y: float = 0.01
const BREATH_AMPLITUDE_X: float = 0.005

# 3. Dynamic Sprint FOV
const SPRINT_FOV: float = 80.0
const FOV_TRANSITION_SPEED: float = 8.0

# 4. Camera Tilt (Roll pada sumbu Z saat Strafe A/D)
const STRAFE_TILT_ANGLE: float = deg_to_rad(1.8) # Miring 1.8 derajat
const TILT_SPEED: float = 7.0

# 5. Landing Compression (Spring Recovery)
const SPRING_STIFFNESS: float = 160.0
const SPRING_DAMPING: float = 15.0

# 6. Flashlight Angular Inertia (Sway / Lag)
const SWAY_AMOUNT: float = 0.0015
const SWAY_MAX: float = 0.15 # Batas maksimal rotasi lag (~8.6 derajat, clampf -0.15 sampai 0.15)
const SWAY_RETURN_SPEED: float = 7.0
const SWAY_SMOOTH_SPEED: float = 11.0

# ==============================================================================
# PENGATURAN SENTER & TERMODINAMIKA (ANTI-FEATHERING)
# ==============================================================================
const HEAT_RATE: float = 18.0
const COOL_RATE: float = 10.0           # Diperlambat dari 22.0/20.0 ke 10.0 per detik
const IGNITION_HEAT_SPIKE: float = 15.0 # Penalti panas instan saat saklar dinyalakan
const COOLING_DELAY: float = 1.8         # Jeda sebelum mulai dingin saat senter dimatikan
const WARNING_HEAT: float = 75.0
const MAX_HEAT: float = 100.0
const OVERHEAT_COOLDOWN: float = 4.0
const FLICKER_INTERVAL: float = 0.08    # Interval flicker 0.08s untuk kedipan nyata

# ==============================================================================
# PENGATURAN ECHOLOCATION DYNAMICS (WALL TAP VS FLOOR FALLBACK)
# ==============================================================================
@export_group("Echolocation Dynamics")
@export var wall_tap_max_radius: float = 16.0  # Radius besar saat mengetuk dinding (< 1.5m)
@export var floor_tap_max_radius: float = 4.5  # Radius saat di ruang terbuka (fallback lantai)
@export var wall_reach_distance: float = 1.5   # Jarak maksimal tangan ke dinding
@export var wave_speed: float = 11.5          # 11.5 m/s (~2x sprint 5.8 m/s, terbaca jelas oleh mata)
@export var tap_cooldown: float = 3.0          # Cooldown antar ketukan
@export var secondary_audio_delay: float = 0.14

# ==============================================================================
# PENGATURAN INTERAKSI
# ==============================================================================
@export_group("Interaction")
@export var interact_distance: float = 2.5

# ==============================================================================
# AUDIO ASSETS & NODES
# ==============================================================================
@export_group("Audio Assets")
@export var footstep_sounds: Array[AudioStream] = []
@export var switch_sound: AudioStream
@export var echo_sound: AudioStream
@export var landing_sound: AudioStream

# Node References
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var footstep_player: AudioStreamPlayer3D = get_node_or_null("FootstepPlayer")
@onready var landing_player: AudioStreamPlayer3D = get_node_or_null("LandingPlayer")
@onready var flashlight_player: AudioStreamPlayer = get_node_or_null("FlashlightPlayer")
@onready var tap_echo_player: AudioStreamPlayer3D = get_node_or_null("TapEchoPlayer")
@onready var view_model: CanvasLayer = get_node_or_null("ViewModel")

# Locomotion & State
var is_sprinting: bool = false
var was_on_floor: bool = true
var previous_vertical_velocity: float = 0.0

# Flashlight State
var is_flashlight_on: bool = false
var is_overheated: bool = false
var current_heat: float = 0.0
var overheat_timer: float = 0.0
var cooling_delay_timer: float = 0.0
var flicker_timer: float = 0.0
var initial_light_energy: float = 8.0
var initial_spot_angle: float = 45.0
var mouse_input_accumulator: Vector2 = Vector2.ZERO
var sway_target: Vector3 = Vector3.ZERO

# Camera & Immersion Dynamic Variables
var initial_camera_pos: Vector3 = Vector3.ZERO
var base_fov: float = 75.0
var bob_time: float = 0.0
var breath_time: float = 0.0
var current_bob_x: float = 0.0
var current_bob_y: float = 0.0
var current_roll_tilt: float = 0.0
var landing_spring_vel: float = 0.0
var landing_compression_y: float = 0.0
var is_step_triggered: bool = false

# Echolocation Wave State
var is_wave_active: bool = false
var wave_radius: float = 0.0
var tap_cooldown_timer: float = 0.0
var active_max_radius: float = 16.0

# Signals
signal flashlight_exploded(player_position: Vector3)
signal footstep_stepped(is_sprint: bool)
signal interaction_failed_in_dark() # Untuk memicu teks UI / suara gumaman bingung

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	flashlight.visible = false
	initial_camera_pos = camera.position
	base_fov = camera.fov
	was_on_floor = is_on_floor()
	initial_light_energy = flashlight.light_energy
	initial_spot_angle = flashlight.spot_angle

	# Pastikan gelombang shader mati saat mulai
	RenderingServer.global_shader_parameter_set("tap_radius", 0.0)

	# Inisialisasi fallback audio jika belum diisi di inspector
	_init_audio_fallbacks()

	if view_model and view_model.has_method("update_flashlight_visual"):
		view_model.update_flashlight_visual(false)

func _init_audio_fallbacks() -> void:
	if footstep_sounds.is_empty():
		var default_step = load("res://assets/audio/sfx/footstep.wav")
		if default_step:
			footstep_sounds.append(default_step)
	if switch_sound == null:
		switch_sound = load("res://assets/audio/sfx/switch.wav")
	if echo_sound == null:
		echo_sound = load("res://assets/audio/sfx/echo.wav")
	if landing_sound == null and not footstep_sounds.is_empty():
		landing_sound = footstep_sounds[0]

func _unhandled_input(event: InputEvent) -> void:
	# 1. Melepaskan kursor mouse
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	# 2. Re-capture mouse saat kursor bebas (MOUSE_MODE_VISIBLE)
	if DisplayServer.get_name() != "headless" and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			var vp := get_viewport()
			if vp:
				vp.set_input_as_handled()
		return

	# 3. Mouse Look & Angular Sway Accumulation
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mouse_x: float = event.relative.x
		var mouse_y: float = event.relative.y

		rotate_y(-mouse_x * MOUSE_SENSITIVITY)
		head.rotate_x(-mouse_y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))

		# Akumulasikan input mouse untuk perhitungan sway
		mouse_input_accumulator.x += mouse_x
		mouse_input_accumulator.y += mouse_y

	# 4. Toggle Senter dengan Ignition Heat Spike (Anti-Feathering)
	if event.is_action_pressed("toggle_flashlight"):
		if is_overheated:
			print("Heat: ", snapped(current_heat, 0.1), " | Overheated: ", is_overheated, " (Senter overheat! Menunggu pendinginan...)")
			return

		is_flashlight_on = not is_flashlight_on
		flashlight.visible = is_flashlight_on

		if switch_sound and flashlight_player:
			flashlight_player.stream = switch_sound
			flashlight_player.pitch_scale = randf_range(0.96, 1.04)
			flashlight_player.play()

		if flashlight.visible:
			# Penalti lonjakan panas instan saat saklar dinyalakan (+15.0)
			current_heat += IGNITION_HEAT_SPIKE
			cooling_delay_timer = COOLING_DELAY
			flicker_timer = 0.0
			if current_heat >= MAX_HEAT:
				trigger_overheat()
		else:
			# Tahan panas selama COOLING_DELAY sebelum mulai dingin
			cooling_delay_timer = COOLING_DELAY
			flashlight.light_energy = initial_light_energy
			flashlight.spot_angle = initial_spot_angle

		print("Heat: ", snapped(current_heat, 0.1), " | Overheated: ", is_overheated)

		if view_model and view_model.has_method("update_flashlight_visual"):
			view_model.update_flashlight_visual(flashlight.visible and not is_overheated)

	# 5. Trigger Echolocation (Dibatasi Cooldown & Tidak saat senter nyala)
	if event.is_action_pressed("wall_tap") and not is_flashlight_on and not is_wave_active and tap_cooldown_timer <= 0.0:
		trigger_surface_tap()

	# 6. Interaksi Objek (Wajib Senter Menyala)
	if event.is_action_pressed("interact"):
		try_interact()

func _physics_process(delta: float) -> void:
	# Gravitasi
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Arah input locomotion
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	is_sprinting = Input.is_action_pressed("sprint") and direction.length() > 0.1
	var current_speed: float = SPRINT_SPEED if is_sprinting else WALK_SPEED

	# Reduksi kontrol udara (AIR_CONTROL_FACTOR = 0.25)
	var accel: float = ACCELERATION if is_on_floor() else (ACCELERATION * AIR_CONTROL_FACTOR)
	var decel: float = DECELERATION if is_on_floor() else (DECELERATION * AIR_CONTROL_FACTOR * 0.25)

	# Pengereman & akselerasi proporsional terhadap delta
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * current_speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)
		velocity.z = move_toward(velocity.z, 0.0, decel * delta)

	# Deteksi Landing Compression saat menyentuh tanah setelah jatuh bebas
	if not was_on_floor and is_on_floor():
		if previous_vertical_velocity < -1.5:
			var impact_force: float = clampf(abs(previous_vertical_velocity) * 0.25, 0.4, 2.2)
			landing_spring_vel -= impact_force
			_trigger_landing(previous_vertical_velocity)

	was_on_floor = is_on_floor()
	previous_vertical_velocity = velocity.y

	move_and_slide()

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	handle_camera_immersion(delta, input_dir, horizontal_speed)
	update_flashlight_sway(delta)
	handle_flashlight_heat(delta)
	handle_tap_wave(delta)

# ==============================================================================
# KAMERA & IMERSI FISIK
# ==============================================================================
func handle_camera_immersion(delta: float, input_dir: Vector2, horizontal_speed: float) -> void:
	# 1. Dynamic Sprint FOV
	var target_fov: float = SPRINT_FOV if is_sprinting else base_fov
	camera.fov = lerp(camera.fov, target_fov, FOV_TRANSITION_SPEED * delta)

	# 2. Camera Tilt (Roll pada sumbu Z saat strafe A/D)
	var target_tilt: float = -input_dir.x * STRAFE_TILT_ANGLE
	current_roll_tilt = lerp(current_roll_tilt, target_tilt, TILT_SPEED * delta)
	camera.rotation.z = current_roll_tilt

	# 3. Landing Compression (Spring-Damper Simulation)
	var spring_accel: float = -SPRING_STIFFNESS * landing_compression_y - SPRING_DAMPING * landing_spring_vel
	landing_spring_vel += spring_accel * delta
	landing_compression_y += landing_spring_vel * delta
	landing_compression_y = clamp(landing_compression_y, -0.12, 0.04)

	# 4. Asymmetric Head Bobbing & Idle Breathing
	var bob_offset: Vector3 = Vector3.ZERO
	var breath_offset: Vector3 = Vector3.ZERO

	if is_on_floor() and horizontal_speed > 0.1:
		var freq: float = BOB_FREQUENCY_SPRINT if is_sprinting else BOB_FREQUENCY_WALK
		var amp: float = BOB_AMPLITUDE_SPRINT if is_sprinting else BOB_AMPLITUDE_WALK
		bob_time += freq * delta

		# Kurva hentakan tumit (abs(sin)): sentakan tajam di lembah terendah
		var heel_strike: float = -abs(sin(bob_time))
		current_bob_y = heel_strike * amp
		current_bob_x = cos(bob_time * 0.5) * (amp * 0.5)
		bob_offset.y = current_bob_y
		bob_offset.x = current_bob_x

		# Footstep Step Trigger: Deteksi lembah terendah siklus langkah
		if abs(sin(bob_time)) > 0.85:
			if not is_step_triggered:
				is_step_triggered = true
				_trigger_footstep(is_sprinting)
		elif abs(sin(bob_time)) < 0.3:
			is_step_triggered = false
	else:
		is_step_triggered = false
		current_bob_y = lerp(current_bob_y, 0.0, BOB_RESET_SPEED * delta)
		current_bob_x = lerp(current_bob_x, 0.0, BOB_RESET_SPEED * delta)
		bob_offset.y = current_bob_y
		bob_offset.x = current_bob_x

		# Idle Breathing (Frekuensi 0.35 Hz) saat karakter diam
		breath_time += 2.0 * PI * BREATH_FREQUENCY * delta
		breath_offset.y = sin(breath_time) * BREATH_AMPLITUDE_Y
		breath_offset.x = cos(breath_time * 0.5) * BREATH_AMPLITUDE_X

	# Komposisi posisi kamera final
	camera.position = initial_camera_pos + bob_offset + breath_offset + Vector3(0.0, landing_compression_y, 0.0)

func _trigger_footstep(sprint: bool) -> void:
	emit_signal("footstep_stepped", sprint)
	if footstep_player:
		footstep_player.pitch_scale = randf_range(0.88, 1.12)
		if not footstep_sounds.is_empty():
			var chosen_stream = footstep_sounds.pick_random()
			if chosen_stream:
				footstep_player.stream = chosen_stream
		if footstep_player.stream:
			footstep_player.play()

func _trigger_landing(impact_vel: float) -> void:
	if landing_player:
		landing_player.pitch_scale = randf_range(0.88, 1.08)
		if landing_sound:
			landing_player.stream = landing_sound
		elif not footstep_sounds.is_empty():
			landing_player.stream = footstep_sounds[0]
		if landing_player.stream:
			landing_player.play()

func update_flashlight_sway(delta: float) -> void:
	# Hitung target sway bertanda positif terhadap mouse_input_accumulator:
	# - Mouse ke Kanan (+x) -> target_sway_y > 0 (rotasi Y positif di Godot = hadap Kiri / tertinggal)
	# - Mouse ke Kiri  (-x) -> target_sway_y < 0 (rotasi Y negatif di Godot = hadap Kanan / tertinggal)
	# - Mouse ke Atas  (-y) -> target_sway_x < 0 (rotasi X negatif di Godot = hadap Bawah / tertinggal)
	# - Mouse ke Bawah (+y) -> target_sway_x > 0 (rotasi X positif di Godot = hadap Atas / tertinggal)
	var target_sway_y: float = clampf(mouse_input_accumulator.x * SWAY_AMOUNT, -SWAY_MAX, SWAY_MAX)
	var target_sway_x: float = clampf(mouse_input_accumulator.y * SWAY_AMOUNT, -SWAY_MAX, SWAY_MAX)

	# Akumulasikan ke sway_target dan batasi dengan clampf (-0.15 hingga 0.15)
	sway_target.y = clampf(sway_target.y + target_sway_y, -SWAY_MAX, SWAY_MAX)
	sway_target.x = clampf(sway_target.x + target_sway_x, -SWAY_MAX, SWAY_MAX)

	# Reset accumulator setelah diproses
	mouse_input_accumulator = Vector2.ZERO

	# Pemulihan target sway ke titik tengah (0, 0, 0)
	sway_target = sway_target.lerp(Vector3.ZERO, SWAY_RETURN_SPEED * delta)

	# Interpolasi rotasi Spotlight3D mengikuti inersia gerakan pandangan
	flashlight.rotation = flashlight.rotation.lerp(sway_target, SWAY_SMOOTH_SPEED * delta)

func handle_flashlight_sway(delta: float) -> void:
	update_flashlight_sway(delta)

# ==============================================================================
# TERMODINAMIKA SENTER & OVERHEAT (ANTI-FEATHERING)
# ==============================================================================
func handle_flashlight_heat(delta: float) -> void:
	if is_overheated:
		overheat_timer -= delta
		if overheat_timer <= 0.0:
			is_overheated = false
			current_heat = 0.0
			print("Senter pulih dari overheat! Siap digunakan kembali.")
			if view_model and view_model.has_method("play_overheat_warning"):
				view_model.play_overheat_warning(false)
		return

	if flashlight.visible:
		cooling_delay_timer = COOLING_DELAY
		current_heat = min(current_heat + HEAT_RATE * delta, MAX_HEAT)
		if current_heat >= MAX_HEAT:
			trigger_overheat()
			return

		if current_heat >= WARNING_HEAT:
			flicker_timer += delta
			if flicker_timer >= FLICKER_INTERVAL:
				flicker_timer = 0.0
				# Kedip mati-nyala biner nyata: 0.0 (mati sesaat) vs initial_light_energy (menyala)
				var is_flicker_dark := randf() < 0.42
				flashlight.light_energy = 0.0 if is_flicker_dark else initial_light_energy
				# Goyangkan sedikit spot_angle agar kedipan terlihat jelas di shader noir
				flashlight.spot_angle = clampf(initial_spot_angle + randf_range(-3.5, 3.5), 25.0, 60.0)
		else:
			flashlight.light_energy = initial_light_energy
			flashlight.spot_angle = initial_spot_angle
	else:
		# Tahan panas selama COOLING_DELAY sebelum mulai turun
		if cooling_delay_timer > 0.0:
			cooling_delay_timer -= delta
		else:
			current_heat = max(current_heat - COOL_RATE * delta, 0.0)
		flashlight.light_energy = initial_light_energy
		flashlight.spot_angle = initial_spot_angle

func trigger_overheat() -> void:
	current_heat = MAX_HEAT
	is_overheated = true
	is_flashlight_on = false
	flashlight.visible = false
	flashlight.light_energy = initial_light_energy
	flashlight.spot_angle = initial_spot_angle
	overheat_timer = OVERHEAT_COOLDOWN
	print("Heat: ", snapped(current_heat, 0.1), " | Overheated: ", is_overheated, " (OVERHEAT! Senter padam selama 4 detik)")
	if view_model and view_model.has_method("play_overheat_warning"):
		view_model.play_overheat_warning(true)
	var emit_pos: Vector3 = global_position if is_inside_tree() else position
	flashlight_exploded.emit(emit_pos)

# ==============================================================================
# SISTEM INTERAKSI OBJEK (ASIMETRI INFORMASI - WAJIB SENTER)
# ==============================================================================
func try_interact() -> void:
	var space_state := get_world_3d().direct_space_state
	var cam_from := camera.global_position
	var cam_to := cam_from + (-camera.global_transform.basis.z * interact_distance)

	var query := PhysicsRayQueryParameters3D.create(cam_from, cam_to)
	query.exclude = [self.get_rid()]
	var result := space_state.intersect_ray(query)

	if result and result.has("collider") and result.collider:
		var target: Node = result.collider
		var interact_target: Node = target
		# Periksa collider, parent, atau owner untuk grup "interactable" atau method interact()
		if not (interact_target.has_method("interact") or interact_target.is_in_group("interactable")):
			if target.get_parent() and (target.get_parent().has_method("interact") or target.get_parent().is_in_group("interactable")):
				interact_target = target.get_parent()
			elif target.owner and (target.owner.has_method("interact") or target.owner.is_in_group("interactable")):
				interact_target = target.owner

		if interact_target.has_method("interact") or interact_target.is_in_group("interactable"):
			# Pemain wajib menyalakan senter untuk berinteraksi
			if flashlight.visible and not is_overheated:
				if interact_target.has_method("interact"):
					interact_target.interact(self)
				else:
					print("Berhasil berinteraksi dengan objek!")
			else:
				interaction_failed_in_dark.emit()
				# Goyang kamera kecil saat gagal interaksi dalam gelap
				landing_spring_vel -= 0.7
				if interact_target.has_method("interact_in_dark"):
					interact_target.interact_in_dark(self)
				else:
					print("Gelap gulita! Nyalakan senter untuk berinteraksi.")

# ==============================================================================
# GELOMBANG ECHOLOCATION (WALL TAP VS FLOOR FALLBACK & COOLDOWN)
# ==============================================================================
func trigger_surface_tap() -> void:
	var space_state := get_world_3d().direct_space_state
	# Cek arah pandangan kamera serta arah horizontal (Depan, Kiri, Kanan) dalam jangkauan tangan (1.5m)
	var wall_directions := [
		-camera.global_transform.basis.z,
		-global_transform.basis.z,
		-global_transform.basis.x,
		global_transform.basis.x
	]

	var closest_hit_pos: Vector3 = Vector3.ZERO
	var min_distance: float = 999.0
	var hit_wall: bool = false

	for dir in wall_directions:
		var ray_origin := head.global_position - Vector3(0.0, 0.25, 0.0) # Setinggi dada/tangan
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + dir * wall_reach_distance)
		query.exclude = [self.get_rid()]
		var result := space_state.intersect_ray(query)

		if result:
			var dist: float = ray_origin.distance_to(result.position)
			if dist < min_distance:
				min_distance = dist
				closest_hit_pos = result.position
				hit_wall = true

	var origin: Vector3
	if hit_wall:
		# KONDISI A: Tangan mengetuk tembok/pilar -> Sonar Kuat (16m)
		origin = closest_hit_pos
		active_max_radius = wall_tap_max_radius
	else:
		# KONDISI B: Ruang terbuka -> Hentakan kaki lemah di lantai (4.5m)
		origin = global_position - Vector3(0.0, 0.9, 0.0)
		active_max_radius = floor_tap_max_radius

	if echo_sound and tap_echo_player:
		tap_echo_player.global_position = origin
		tap_echo_player.pitch_scale = randf_range(0.98, 1.04) if hit_wall else randf_range(0.75, 0.85)
		tap_echo_player.volume_db = 0.0 if hit_wall else -6.0
		tap_echo_player.stream = echo_sound
		tap_echo_player.play()

		# Double ping hanya aktif jika mengetuk dinding/pilar
		if hit_wall:
			get_tree().create_timer(secondary_audio_delay).timeout.connect(func():
				if is_instance_valid(tap_echo_player) and echo_sound:
					var p2 := AudioStreamPlayer3D.new()
					p2.bus = tap_echo_player.bus
					p2.max_distance = tap_echo_player.max_distance
					p2.stream = echo_sound
					p2.pitch_scale = randf_range(1.08, 1.15)
					p2.volume_db = tap_echo_player.volume_db - 3.0
					get_tree().current_scene.add_child(p2)
					p2.global_position = origin
					p2.play()
					p2.finished.connect(p2.queue_free)
			)

	# Recoil visual pada tangan (ViewModel)
	if view_model and view_model.has_method("play_tap_recoil"):
		view_model.play_tap_recoil()

	RenderingServer.global_shader_parameter_set("tap_origin", origin)
	is_wave_active = true
	wave_radius = 0.0
	tap_cooldown_timer = tap_cooldown
	print("Tap! ", "Dinding (16m)" if hit_wall else "Lantai (4.5m)", " dari: ", origin)

func handle_tap_wave(delta: float) -> void:
	if tap_cooldown_timer > 0.0:
		tap_cooldown_timer -= delta

	if not is_wave_active:
		return

	wave_radius += wave_speed * delta
	RenderingServer.global_shader_parameter_set("tap_radius", wave_radius)

	if wave_radius >= (active_max_radius + 2.0):
		is_wave_active = false
		wave_radius = 0.0
		RenderingServer.global_shader_parameter_set("tap_radius", 0.0)
