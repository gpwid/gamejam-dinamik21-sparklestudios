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
# PENGATURAN SENTER OVERHEAT & WARNING SYSTEM
# ==============================================================================
const MAX_HEAT: float = 100.0
const HEAT_RATE: float = 15.0
const COOL_RATE: float = 20.0
const WARNING_HEAT: float = 70.0
const CRITICAL_HEAT: float = 85.0
const OVERHEAT_COOLDOWN: float = 4.0

# Interval Flicker Heat Warning (~0.12s interval pencegah strobe hazard)
const WARNING_INTERVAL_MIN: float = 0.10
const WARNING_INTERVAL_MAX: float = 0.14

# Interval Flicker Critical Warning (Intens & tidak teratur)
const CRITICAL_LIGHT_TIME_MIN: float = 0.06
const CRITICAL_LIGHT_TIME_MAX: float = 0.14
const CRITICAL_DROP_TIME_MIN: float = 0.04
const CRITICAL_DROP_TIME_MAX: float = 0.09

# ==============================================================================
# PENGATURAN GELOMBANG ECHOLOCATION (DOUBLE-WAVE & AFTERGLOW TRAIL)
# ==============================================================================
const TAP_REACH_DISTANCE: float = 3.0       # Jarak jangkauan tangan meraba dinding (meter)
const WAVE_SPEED: float = 8.5               # Kecepatan rambat visual (8.5 m/s, mendahului lari pemain 6.0 m/s)
const WAVE_VISUAL_DURATION: float = 2.0     # Durasi ekspansi visual terbaca (2.0 detik)
const MAX_WAVE_RADIUS: float = 17.0         # Jangkauan maksimal rambat gelombang (meter)
const DOUBLE_PING_DELAY: float = 0.28       # Jeda pemutaran audio echo kedua (detik)

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
var flicker_timer: float = 0.0
var is_flicker_dark: bool = false
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
var wave_visual_timer: float = 0.0
var current_tap_radius: float = 0.0

# Signals
signal flashlight_exploded(player_position: Vector3)
signal footstep_stepped(is_sprint: bool)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	flashlight.visible = false
	initial_camera_pos = camera.position
	base_fov = camera.fov
	was_on_floor = is_on_floor()

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
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
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
		
	# 4. Toggle Flashlight
	if event.is_action_pressed("toggle_flashlight") and not is_overheated:
		is_flashlight_on = !is_flashlight_on
		flashlight.visible = is_flashlight_on
		flashlight.light_energy = 1.0
		flicker_timer = 0.0
		is_flicker_dark = false

		# Mainkan suara switch senter
		if flashlight_player:
			flashlight_player.pitch_scale = randf_range(0.95, 1.05)
			if switch_sound:
				flashlight_player.stream = switch_sound
			if flashlight_player.stream:
				flashlight_player.play()

		if view_model and view_model.has_method("update_flashlight_visual"):
			view_model.update_flashlight_visual(is_flashlight_on)
		
	# 5. Wall-Tap / Floor-Tap Echolocation
	if event.is_action_pressed("wall_tap") and not is_flashlight_on and not is_wave_active:
		trigger_surface_tap()

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

# Alias fungsi untuk kompatibilitas
func handle_flashlight_sway(delta: float) -> void:
	update_flashlight_sway(delta)

# ==============================================================================
# SENTER HEAT & WARNING FLICKER
# ==============================================================================
func handle_flashlight_heat(delta: float) -> void:
	if is_overheated:
		overheat_timer -= delta
		if overheat_timer <= 0.0:
			is_overheated = false
			current_heat = 0.0
			if view_model and view_model.has_method("play_overheat_warning"):
				view_model.play_overheat_warning(false)
		return

	if is_flashlight_on:
		current_heat += HEAT_RATE * delta
		
		# 1. Critical Warning (heat >= CRITICAL_HEAT): Flicker intens & tidak teratur
		if current_heat >= CRITICAL_HEAT:
			flicker_timer -= delta
			if flicker_timer <= 0.0:
				if is_flicker_dark:
					is_flicker_dark = false
					flashlight.visible = true
					flashlight.light_energy = 1.0
					flicker_timer = randf_range(CRITICAL_LIGHT_TIME_MIN, CRITICAL_LIGHT_TIME_MAX)
					if view_model and view_model.has_method("update_flashlight_visual"):
						view_model.update_flashlight_visual(true)
				else:
					is_flicker_dark = true
					flashlight.visible = false
					flashlight.light_energy = 0.0
					flicker_timer = randf_range(CRITICAL_DROP_TIME_MIN, CRITICAL_DROP_TIME_MAX)
					if view_model and view_model.has_method("update_flashlight_visual"):
						view_model.update_flashlight_visual(false)

		# 2. Heat Warning (heat >= WARNING_HEAT): Interval noise halus (~0.12s) pencegah strobe hazard
		elif current_heat >= WARNING_HEAT:
			flicker_timer -= delta
			if flicker_timer <= 0.0:
				flicker_timer = randf_range(WARNING_INTERVAL_MIN, WARNING_INTERVAL_MAX)
				if is_flicker_dark:
					is_flicker_dark = false
					flashlight.visible = true
					flashlight.light_energy = 1.0
					if view_model and view_model.has_method("update_flashlight_visual"):
						view_model.update_flashlight_visual(true)
				else:
					# 25% peluang drop singkat pada interval ini, tidak terus-menerus on-off
					if randf() < 0.25:
						is_flicker_dark = true
						flashlight.visible = false
						flashlight.light_energy = 0.0
						flicker_timer = 0.05
						if view_model and view_model.has_method("update_flashlight_visual"):
							view_model.update_flashlight_visual(false)

		# 3. Normal (heat < WARNING_HEAT): Stabil menyala dan tidak berkedip
		else:
			is_flicker_dark = false
			flashlight.visible = true
			flashlight.light_energy = 1.0
			flicker_timer = 0.0
			if view_model and view_model.has_method("update_flashlight_visual"):
				view_model.update_flashlight_visual(true)
			
		# 4. Overheated (heat >= MAX_HEAT): Padam total dan masuk cooldown
		if current_heat >= MAX_HEAT:
			is_overheated = true
			is_flashlight_on = false
			flashlight.visible = false
			flashlight.light_energy = 1.0
			is_flicker_dark = false
			flicker_timer = 0.0
			overheat_timer = OVERHEAT_COOLDOWN
			if view_model and view_model.has_method("play_overheat_warning"):
				view_model.play_overheat_warning(true)
			emit_signal("flashlight_exploded", global_position)
	else:
		# 5. Recovery saat senter dimatikan secara manual
		current_heat = move_toward(current_heat, 0.0, COOL_RATE * delta)
		is_flicker_dark = false
		flashlight.visible = false
		flashlight.light_energy = 1.0
		flicker_timer = 0.0
		if view_model and view_model.has_method("update_flashlight_visual"):
			view_model.update_flashlight_visual(false)

# ==============================================================================
# GELOMBANG ECHOLOCATION (WALL-TAP) & AFTERGLOW TRAIL
# ==============================================================================
func handle_tap_wave(delta: float) -> void:
	if not is_wave_active:
		return

	wave_visual_timer += delta
	var progress: float = clampf(wave_visual_timer / WAVE_VISUAL_DURATION, 0.0, 1.0)
	
	# Ekspansi terbaca dengan kecepatan stabil (~8.5 m/s)
	current_tap_radius = lerpf(0.0, MAX_WAVE_RADIUS, progress)
	RenderingServer.global_shader_parameter_set("tap_radius", current_tap_radius)

	# Selesai merambat visual dalam 2.0 detik
	if progress >= 1.0:
		is_wave_active = false
		wave_visual_timer = 0.0
		current_tap_radius = 0.0
		RenderingServer.global_shader_parameter_set("tap_radius", 0.0)

func trigger_surface_tap() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = camera.global_position
	
	# Daftar arah cek: 1. Depan, 2. Kanan, 3. Kiri, 4. Lantai di bawah kaki
	var check_directions: Array[Vector3] = [
		-camera.global_transform.basis.z * TAP_REACH_DISTANCE,
		camera.global_transform.basis.x * TAP_REACH_DISTANCE,
		-camera.global_transform.basis.x * TAP_REACH_DISTANCE,
		Vector3(0.0, -2.5, 0.0)
	]
	
	var closest_hit_pos: Vector3 = global_position - Vector3(0.0, 0.9, 0.0)
	var min_dist: float = 999.0
	
	for dir in check_directions:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir)
		query.exclude = [self.get_rid()]
		var result: Dictionary = space_state.intersect_ray(query)
		if result:
			var dist: float = origin.distance_to(result.position)
			if dist < min_dist:
				min_dist = dist
				closest_hit_pos = result.position
	
	# Mulai ekspansi gelombang shader
	RenderingServer.global_shader_parameter_set("tap_origin", closest_hit_pos)
	RenderingServer.global_shader_parameter_set("tap_radius", 0.0)
	wave_visual_timer = 0.0
	current_tap_radius = 0.0
	is_wave_active = true

	# 1. Putar audio TapEchoPlayer ping pertama di titik kontak permukaan (origin)
	if tap_echo_player:
		tap_echo_player.global_position = closest_hit_pos
		if echo_sound:
			tap_echo_player.stream = echo_sound
		if tap_echo_player.stream:
			tap_echo_player.pitch_scale = 1.0
			tap_echo_player.play()

	# 2. Double Audio Ping: Picu gema kedua seirama dengan cincin kedua (~0.28s)
	get_tree().create_timer(DOUBLE_PING_DELAY).timeout.connect(func():
		if is_instance_valid(tap_echo_player) and tap_echo_player.stream:
			tap_echo_player.pitch_scale = randf_range(0.96, 1.04)
			tap_echo_player.play()
	)

	# 3. Recoil visual pada tangan (ViewModel)
	if view_model and view_model.has_method("play_tap_recoil"):
		view_model.play_tap_recoil()

	print("Tap! Echolocation double-wave aktif dari: ", closest_hit_pos, " | Kecepatan: ", WAVE_SPEED, " m/s | Durasi: ", WAVE_VISUAL_DURATION, "s")
