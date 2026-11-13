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
const WALL_STOP_THRESHOLD: float = 0.82  # Tabrakan < ~35 derajat dari tegak lurus = berhenti total
const WALL_SLIDE_SPEED_MULT: float = 0.6 # Kecepatan merayap saat sliding miring di tembok
var is_sliding_on_wall: bool = false

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
# PENGATURAN SENTER OVERHEAT, ANTI-FEATHERING & WARNING SYSTEM
# ==============================================================================
const MAX_HEAT: float = 100.0
const HEAT_RATE: float = 15.0
const COOL_RATE: float = 10.0           # Diperlambat agar tidak bisa spam nyala-mati
const IGNITION_HEAT_SPIKE: float = 15.0 # Penalti panas instan setiap klik nyala
const COOLING_DELAY: float = 1.8        # Jeda tahan panas sebelum mulai dingin
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
# PENGATURAN GELOMBANG ECHOLOCATION (PERSISTENT REVEAL & SIMULTANEOUS FADE)
# ==============================================================================
@export_group("Echolocation Dynamics")
@export var wall_reach_distance: float = 1.8   # Jarak tangan menyentuh dinding (meter)
@export var wall_tap_max_radius: float = 17.0  # Jangkauan maksimal saat mengetuk dinding
@export var floor_tap_max_radius: float = 6.0  # Jangkauan terbatas saat di ruang terbuka
@export var wave_speed: float = 16.0           # 16.0 m/s (Cepat & ekspansif)
@export var wave_hold_duration: float = 0.35   # Tahan visibilitas penuh (detik)
@export var wave_fade_duration: float = 1.2    # Fade-out serentak seluruh ruangan (detik)
@export var tap_cooldown: float = 1.5          # Cooldown jeda gelap setelah fade selesai (detik)
@export var double_ping_delay: float = 0.22    # Jeda pemutaran audio echo kedua (detik)

# ==============================================================================
# DEBUG OPTIONS
# ==============================================================================
@export_group("Debug")
@export var debug_infinite_flashlight: bool = false

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

# Node References (Termasuk OutlinePass dari branch main!)
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var footstep_player: AudioStreamPlayer3D = get_node_or_null("FootstepPlayer")
@onready var landing_player: AudioStreamPlayer3D = get_node_or_null("LandingPlayer")
@onready var flashlight_player: AudioStreamPlayer = get_node_or_null("FlashlightPlayer")
@onready var tap_echo_player: AudioStreamPlayer3D = get_node_or_null("TapEchoPlayer")
@onready var outline_pass: MeshInstance3D = get_node_or_null("Head/Camera3D/OutlinePass")
@onready var view_model: CanvasLayer = get_node_or_null("ViewModel")

var outline_material: ShaderMaterial

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
enum WavePhase { IDLE, EXPAND, HOLD, FADE }
var wave_phase: WavePhase = WavePhase.IDLE
var wave_timer: float = 0.0
var is_wave_active: bool = false
var current_tap_radius: float = 0.0
var shader_tap_radius: float = 0.0
var active_max_radius: float = 17.0
var tap_cooldown_timer: float = 0.0

# Signals
signal flashlight_exploded(player_position: Vector3)
signal footstep_stepped(is_sprint: bool)
signal interaction_failed_in_dark()

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	flashlight.visible = false
	flashlight.light_energy = 1.0
	initial_camera_pos = camera.position
	base_fov = camera.fov
	was_on_floor = is_on_floor()

	_set_tap_radius(0.0)
	_init_audio_fallbacks()

	if view_model and view_model.has_method("update_flashlight_visual"):
		view_model.update_flashlight_visual(false)
	if outline_pass:
		outline_pass.visible = true
		outline_material = outline_pass.get_active_material(0) as ShaderMaterial
		if outline_material:
			outline_material.set_shader_parameter("flashlight_view_pos", flashlight.position)
			outline_material.set_shader_parameter("flashlight_view_dir", -flashlight.transform.basis.z.normalized())
			outline_material.set_shader_parameter("flashlight_cos_angle", cos(deg_to_rad(flashlight.spot_angle)))
			outline_material.set_shader_parameter("flashlight_range", flashlight.spot_range)
			outline_material.set_shader_parameter("flashlight_on", false)

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

		mouse_input_accumulator.x += mouse_x
		mouse_input_accumulator.y += mouse_y

	# Debug: Toggle Infinite Flashlight dengan tombol F1
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		debug_infinite_flashlight = !debug_infinite_flashlight
		if debug_infinite_flashlight:
			is_overheated = false
			current_heat = 0.0
			overheat_timer = 0.0
			if view_model and view_model.has_method("play_overheat_warning"):
				view_model.play_overheat_warning(false)
		print("[DEBUG] Infinite Flashlight: ", "AKTIF (Permanen)" if debug_infinite_flashlight else "NONAKTIF")

	# 4. Toggle Flashlight + Ignition Heat Spike (Anti-Feathering)
	if event.is_action_pressed("toggle_flashlight"):
		if is_overheated:
			if debug_infinite_flashlight:
				is_overheated = false
				current_heat = 0.0
			else:
				print("Heat: ", snapped(current_heat, 0.1), " | Overheated: true (Menunggu dingin...)")
				return

		is_flashlight_on = !is_flashlight_on
		flashlight.visible = is_flashlight_on
		flashlight.light_energy = 1.0
		flicker_timer = 0.0
		is_flicker_dark = false
		cooling_delay_timer = COOLING_DELAY

		if flashlight_player:
			flashlight_player.pitch_scale = randf_range(0.95, 1.05)
			if switch_sound:
				flashlight_player.stream = switch_sound
			if flashlight_player.stream:
				flashlight_player.play()

		if is_flashlight_on and not debug_infinite_flashlight:
			current_heat += IGNITION_HEAT_SPIKE
			if current_heat >= MAX_HEAT:
				_trigger_overheat()

		print("Heat: ", snapped(current_heat, 0.1), " | Overheated: ", is_overheated)

		if view_model and view_model.has_method("update_flashlight_visual"):
			view_model.update_flashlight_visual(flashlight.visible and not is_overheated)

	# 5. Wall-Tap / Floor-Tap Echolocation (Dengan Cooldown)
	if event.is_action_pressed("wall_tap") and not is_flashlight_on and not is_wave_active and tap_cooldown_timer <= 0.0:
		trigger_surface_tap()

	# 6. Interaksi Objek (Wajib Senter Menyala)
	if event.is_action_pressed("interact"):
		try_interact()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	is_sprinting = Input.is_action_pressed("sprint") and direction.length() > 0.1
	var current_speed: float = SPRINT_SPEED if is_sprinting else WALK_SPEED

	var accel: float = ACCELERATION if is_on_floor() else (ACCELERATION * AIR_CONTROL_FACTOR)
	var decel: float = DECELERATION if is_on_floor() else (DECELERATION * AIR_CONTROL_FACTOR * 0.25)

	if direction:
		velocity.x = move_toward(velocity.x, direction.x * current_speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)
		velocity.z = move_toward(velocity.z, 0.0, decel * delta)

	if not was_on_floor and is_on_floor():
		if previous_vertical_velocity < -1.5:
			var impact_force: float = clampf(abs(previous_vertical_velocity) * 0.25, 0.4, 2.2)
			landing_spring_vel -= impact_force
			_trigger_landing(previous_vertical_velocity)

	was_on_floor = is_on_floor()
	previous_vertical_velocity = velocity.y

	move_and_slide()

	# Deteksi Tabrakan Dinding (Head-On Stop vs. Angled Wall Sliding)
	is_sliding_on_wall = false
	var real_vel := get_real_velocity()
	var horizontal_speed: float = Vector2(real_vel.x, real_vel.z).length()

	if is_on_wall() and direction.length() > 0.1:
		var wall_normal_h := Vector3(get_wall_normal().x, 0.0, get_wall_normal().z).normalized()
		var into_wall_dot: float = -direction.dot(wall_normal_h)

		if into_wall_dot >= WALL_STOP_THRESHOLD:
			# KONDISI A - TABRAKAN FRONTAL (into_wall_dot >= 0.82): Hentikan paksa gerakan horizontal
			velocity.x = 0.0
			velocity.z = 0.0
			horizontal_speed = 0.0
		elif into_wall_dot > 0.1:
			# KONDISI B - SLIDING MIRING (into_wall_dot > 0.1 dan < 0.82):
			is_sliding_on_wall = true
			is_sprinting = false
			# Redam kecepatan gerak menyusuri dinding sebesar 60% kecepatan jalan
			var max_slide_speed: float = WALK_SPEED * WALL_SLIDE_SPEED_MULT
			var h_vel := Vector2(velocity.x, velocity.z)
			if h_vel.length() > max_slide_speed:
				h_vel = h_vel.normalized() * max_slide_speed
				velocity.x = h_vel.x
				velocity.z = h_vel.y
			horizontal_speed = minf(horizontal_speed, max_slide_speed)

	handle_camera_immersion(delta, input_dir, horizontal_speed)
	update_flashlight_sway(delta)
	handle_flashlight_heat(delta)
	handle_tap_wave(delta)

	if outline_material:
		outline_material.set_shader_parameter("flashlight_on", flashlight.visible and flashlight.light_energy > 0.0)
		outline_material.set_shader_parameter("flashlight_view_dir", -flashlight.transform.basis.z.normalized())
		

# ==============================================================================
# KAMERA & IMERSI FISIK
# ==============================================================================
func handle_camera_immersion(delta: float, input_dir: Vector2, horizontal_speed: float) -> void:
	var target_fov: float = SPRINT_FOV if is_sprinting else base_fov
	camera.fov = lerp(camera.fov, target_fov, FOV_TRANSITION_SPEED * delta)

	var target_tilt: float = -input_dir.x * STRAFE_TILT_ANGLE
	current_roll_tilt = lerp(current_roll_tilt, target_tilt, TILT_SPEED * delta)
	camera.rotation.z = current_roll_tilt

	var spring_accel: float = -SPRING_STIFFNESS * landing_compression_y - SPRING_DAMPING * landing_spring_vel
	landing_spring_vel += spring_accel * delta
	landing_compression_y += landing_spring_vel * delta
	landing_compression_y = clamp(landing_compression_y, -0.12, 0.04)

	var bob_offset: Vector3 = Vector3.ZERO
	var breath_offset: Vector3 = Vector3.ZERO
	var is_moving: bool = is_on_floor() and horizontal_speed > 0.1
	var is_idle: bool = is_on_floor() and not is_moving

	if is_moving:
		var freq: float = BOB_FREQUENCY_SPRINT if is_sprinting else BOB_FREQUENCY_WALK
		var amp: float = BOB_AMPLITUDE_SPRINT if is_sprinting else BOB_AMPLITUDE_WALK

		# Saat sliding dinding, lambatkan frekuensi dan perkecil amplitudo sesuai rasio kecepatan
		if is_sliding_on_wall:
			var speed_ratio: float = clampf(horizontal_speed / WALK_SPEED, 0.4, 1.0)
			freq *= speed_ratio
			amp *= speed_ratio

		bob_time += freq * delta

		var heel_strike: float = -abs(sin(bob_time))
		current_bob_y = heel_strike * amp
		current_bob_x = cos(bob_time * 0.5) * (amp * 0.5)
		bob_offset.y = current_bob_y
		bob_offset.x = current_bob_x

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

		breath_time += 2.0 * PI * BREATH_FREQUENCY * delta
		breath_offset.y = sin(breath_time) * BREATH_AMPLITUDE_Y
		breath_offset.x = cos(breath_time * 0.5) * BREATH_AMPLITUDE_X

	if view_model and view_model.has_method("set_idle"):
		view_model.set_idle(is_idle)

	camera.position = initial_camera_pos + bob_offset + breath_offset + Vector3(0.0, landing_compression_y, 0.0)

func _trigger_footstep(sprint: bool) -> void:
	emit_signal("footstep_stepped", sprint)
	if footstep_player:
		if is_sliding_on_wall:
			footstep_player.volume_db = -11.0
			footstep_player.pitch_scale = randf_range(0.82, 0.94)
		elif sprint:
			footstep_player.volume_db = 1.0
			footstep_player.pitch_scale = randf_range(0.95, 1.15)
		else:
			footstep_player.volume_db = -3.0
			footstep_player.pitch_scale = randf_range(0.88, 1.12)

		if not footstep_sounds.is_empty():
			var chosen_stream = footstep_sounds.pick_random()
			if chosen_stream:
				footstep_player.stream = chosen_stream
		if footstep_player.stream and footstep_player.is_inside_tree():
			footstep_player.play()

func _trigger_landing(impact_vel: float) -> void:
	if landing_player:
		landing_player.pitch_scale = randf_range(0.88, 1.08)
		if landing_sound:
			landing_player.stream = landing_sound
		elif not footstep_sounds.is_empty():
			landing_player.stream = footstep_sounds[0]
		if landing_player.stream and landing_player.is_inside_tree():
			landing_player.play()

func update_flashlight_sway(delta: float) -> void:
	var target_sway_y: float = clampf(mouse_input_accumulator.x * SWAY_AMOUNT, -SWAY_MAX, SWAY_MAX)
	var target_sway_x: float = clampf(mouse_input_accumulator.y * SWAY_AMOUNT, -SWAY_MAX, SWAY_MAX)

	sway_target.y = clampf(sway_target.y + target_sway_y, -SWAY_MAX, SWAY_MAX)
	sway_target.x = clampf(sway_target.x + target_sway_x, -SWAY_MAX, SWAY_MAX)

	mouse_input_accumulator = Vector2.ZERO
	sway_target = sway_target.lerp(Vector3.ZERO, SWAY_RETURN_SPEED * delta)
	flashlight.rotation = flashlight.rotation.lerp(sway_target, SWAY_SMOOTH_SPEED * delta)

func handle_flashlight_sway(delta: float) -> void:
	update_flashlight_sway(delta)

# ==============================================================================
# SENTER HEAT, ANTI-FEATHERING & WARNING FLICKER (ASLI MAIN)
# ==============================================================================
func handle_flashlight_heat(delta: float) -> void:
	if debug_infinite_flashlight:
		if is_overheated:
			is_overheated = false
			current_heat = 0.0
			overheat_timer = 0.0
			if view_model and view_model.has_method("play_overheat_warning"):
				view_model.play_overheat_warning(false)
		current_heat = 0.0
		is_flicker_dark = false
		flicker_timer = 0.0
		flashlight.visible = is_flashlight_on
		flashlight.light_energy = 1.0
		if view_model and view_model.has_method("update_flashlight_visual"):
			view_model.update_flashlight_visual(is_flashlight_on)
		return

	if is_overheated:
		overheat_timer -= delta
		if overheat_timer <= 0.0:
			is_overheated = false
			current_heat = 0.0
			print("Senter pulih dari overheat!")
			if view_model and view_model.has_method("play_overheat_warning"):
				view_model.play_overheat_warning(false)
		return

	if is_flashlight_on:
		cooling_delay_timer = COOLING_DELAY
		current_heat += HEAT_RATE * delta

		# 1. Critical Warning (heat >= CRITICAL_HEAT): Flicker mati-nyala intens
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

		# 2. Heat Warning (heat >= WARNING_HEAT): Kedip mati-nyala berkala
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
					if randf() < 0.25:
						is_flicker_dark = true
						flashlight.visible = false
						flashlight.light_energy = 0.0
						flicker_timer = 0.05
						if view_model and view_model.has_method("update_flashlight_visual"):
							view_model.update_flashlight_visual(false)

		# 3. Normal (heat < WARNING_HEAT): Stabil menyala (light_energy = 1.0)
		else:
			is_flicker_dark = false
			flashlight.visible = true
			flashlight.light_energy = 1.0
			flicker_timer = 0.0
			if view_model and view_model.has_method("update_flashlight_visual"):
				view_model.update_flashlight_visual(true)

		# 4. Overheated (heat >= MAX_HEAT)
		if current_heat >= MAX_HEAT:
			_trigger_overheat()
	else:
		# 5. Recovery dengan Cooling Delay (Anti-Feathering)
		if cooling_delay_timer > 0.0:
			cooling_delay_timer -= delta
		else:
			current_heat = move_toward(current_heat, 0.0, COOL_RATE * delta)
		is_flicker_dark = false
		flashlight.visible = false
		flashlight.light_energy = 1.0
		flicker_timer = 0.0
		if view_model and view_model.has_method("update_flashlight_visual"):
			view_model.update_flashlight_visual(false)

func _trigger_overheat() -> void:
	current_heat = MAX_HEAT
	is_overheated = true
	is_flashlight_on = false
	flashlight.visible = false
	flashlight.light_energy = 1.0
	is_flicker_dark = false
	flicker_timer = 0.0
	overheat_timer = OVERHEAT_COOLDOWN
	print("Heat: 100.0 | OVERHEAT! Senter padam selama 4 detik.")
	if view_model and view_model.has_method("play_overheat_warning"):
		view_model.play_overheat_warning(true)
	emit_signal("flashlight_exploded", global_position)

# ==============================================================================
# SISTEM INTERAKSI OBJEK (WAJIB SENTER MENYALA)
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
		if not (interact_target.has_method("interact") or interact_target.is_in_group("interactable")):
			if target.get_parent() and (target.get_parent().has_method("interact") or target.get_parent().is_in_group("interactable")):
				interact_target = target.get_parent()
			elif target.owner and (target.owner.has_method("interact") or target.owner.is_in_group("interactable")):
				interact_target = target.owner

		if interact_target.has_method("interact") or interact_target.is_in_group("interactable"):
			if is_flashlight_on and not is_overheated:
				if interact_target.has_method("interact"):
					interact_target.interact(self)
				else:
					print("Berhasil berinteraksi dengan objek!")
			else:
				interaction_failed_in_dark.emit()
				landing_spring_vel -= 0.7
				if interact_target.has_method("interact_in_dark"):
					interact_target.interact_in_dark(self)
				else:
					print("Gelap gulita! Nyalakan senter untuk berinteraksi.")

# ==============================================================================
# GELOMBANG ECHOLOCATION (WALL-TAP VS FLOOR FALLBACK & COOLDOWN)
# ==============================================================================
func _set_tap_radius(val: float) -> void:
	shader_tap_radius = val
	RenderingServer.global_shader_parameter_set("tap_radius", val)

func handle_tap_wave(delta: float) -> void:
	if tap_cooldown_timer > 0.0:
		tap_cooldown_timer -= delta

	if not is_wave_active:
		return

	match wave_phase:
		WavePhase.EXPAND:
			current_tap_radius += wave_speed * delta
			if current_tap_radius >= active_max_radius:
				current_tap_radius = active_max_radius
				wave_phase = WavePhase.HOLD
				wave_timer = 0.0
				var encoded_val: float = -(floorf(active_max_radius) + 0.999)
				_set_tap_radius(encoded_val)
			else:
				_set_tap_radius(current_tap_radius)

		WavePhase.HOLD:
			wave_timer += delta
			var encoded_val: float = -(floorf(active_max_radius) + 0.999)
			_set_tap_radius(encoded_val)
			if wave_timer >= wave_hold_duration:
				wave_phase = WavePhase.FADE
				wave_timer = 0.0

		WavePhase.FADE:
			wave_timer += delta
			var progress: float = clampf(wave_timer / wave_fade_duration, 0.0, 1.0)
			var fade_alpha: float = lerpf(0.999, 0.0, progress)
			var encoded_val: float = -(floorf(active_max_radius) + clampf(fade_alpha, 0.001, 0.999))
			_set_tap_radius(encoded_val)

			if progress >= 1.0:
				wave_phase = WavePhase.IDLE
				is_wave_active = false
				current_tap_radius = 0.0
				tap_cooldown_timer = tap_cooldown
				_set_tap_radius(0.0)

func trigger_surface_tap() -> void:
	var world_3d := get_world_3d()
	if not world_3d:
		return
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	var origin: Vector3 = camera.global_position if camera else global_position

	# Cek apakah ada dinding dalam jangkauan tangan (Depan, Kanan, Kiri)
	var wall_directions: Array[Vector3] = [
		-camera.global_transform.basis.z * wall_reach_distance,
		camera.global_transform.basis.x * wall_reach_distance,
		-camera.global_transform.basis.x * wall_reach_distance
	]

	var closest_hit_pos: Vector3 = global_position - Vector3(0.0, 0.9, 0.0)
	var min_dist: float = 999.0
	var hit_wall: bool = false

	for dir in wall_directions:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir)
		query.exclude = [self.get_rid()]
		var result: Dictionary = space_state.intersect_ray(query)
		if result:
			var dist: float = origin.distance_to(result.position)
			if dist < min_dist:
				min_dist = dist
				closest_hit_pos = result.position
				hit_wall = true

	# Jika tidak ada dinding di dekat tangan, cek lantai tepat di bawah kaki
	if not hit_wall:
		var floor_query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(0.0, -2.5, 0.0))
		floor_query.exclude = [self.get_rid()]
		var floor_res: Dictionary = space_state.intersect_ray(floor_query)
		if floor_res:
			closest_hit_pos = floor_res.position

	active_max_radius = wall_tap_max_radius if hit_wall else floor_tap_max_radius

	RenderingServer.global_shader_parameter_set("tap_origin", closest_hit_pos)
	_set_tap_radius(0.0)
	current_tap_radius = 0.0
	wave_timer = 0.0
	wave_phase = WavePhase.EXPAND
	is_wave_active = true
	tap_cooldown_timer = 0.0

	# 1. Putar audio TapEchoPlayer ping pertama
	if tap_echo_player:
		tap_echo_player.global_position = closest_hit_pos
		if echo_sound:
			tap_echo_player.stream = echo_sound
		if tap_echo_player.stream:
			tap_echo_player.pitch_scale = 1.0 if hit_wall else 0.82
			tap_echo_player.volume_db = 0.0 if hit_wall else -5.0
			tap_echo_player.play()

	# 2. Double Audio Ping (khusus saat mengetuk dinding)
	if hit_wall:
		get_tree().create_timer(double_ping_delay).timeout.connect(func():
			if is_instance_valid(tap_echo_player) and tap_echo_player.stream:
				tap_echo_player.pitch_scale = randf_range(0.96, 1.04)
				tap_echo_player.play()
		)

	# 3. Recoil visual pada tangan (ViewModel)
	if view_model and view_model.has_method("play_tap_recoil"):
		view_model.play_tap_recoil()

	print("Tap! ", "Objek (17m)" if hit_wall else "Lantai (6m)", " | Kecepatan: ", wave_speed, " m/s")
