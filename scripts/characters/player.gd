extends CharacterBody3D

# --- PENGATURAN GERAK ---
const WALK_SPEED = 3.0
const SPRINT_SPEED = 6.0
const ACCELERATION = 25.0
const DECELERATION = 25.0
const AIR_ACCELERATION = 5.0
const AIR_DECELERATION = 2.0
const MOUSE_SENSITIVITY = 0.003

# --- PENGATURAN KAMERA (HEAD BOB & SPRINT FOV) ---
const BOB_FREQUENCY_WALK = 10.0
const BOB_FREQUENCY_SPRINT = 20.0
const BOB_AMPLITUDE_WALK = 0.05
const BOB_AMPLITUDE_SPRINT = 0.06
const BOB_RESET_SPEED = 10.0
const SPRINT_FOV = 80.0
const FOV_TRANSITION_SPEED = 8.0

# --- PENGATURAN SENTER OVERHEAT & WARNING ---
const MAX_HEAT = 100.0
const HEAT_RATE = 15.0
const COOL_RATE = 20.0
const WARNING_HEAT = 70.0
const CRITICAL_HEAT = 85.0
const OVERHEAT_COOLDOWN = 4.0

# Interval Flicker Heat Warning (Berkedip sesekali)
const WARNING_LIGHT_TIME_MIN = 0.20
const WARNING_LIGHT_TIME_MAX = 0.45
const WARNING_DROP_TIME_MIN = 0.05
const WARNING_DROP_TIME_MAX = 0.10

# Interval Flicker Critical Warning (Intens & tidak teratur)
const CRITICAL_LIGHT_TIME_MIN = 0.06
const CRITICAL_LIGHT_TIME_MAX = 0.14
const CRITICAL_DROP_TIME_MIN = 0.04
const CRITICAL_DROP_TIME_MAX = 0.09

# --- PENGATURAN GELOMBANG WALL-TAP ---
const TAP_REACH_DISTANCE = 3.0   # Jarak jangkauan tangan meraba dinding (meter)
const TAP_WAVE_SPEED = 2.2      # Kecepatan rambat gelombang (meter per detik)
const TAP_MAX_RADIUS = 8.0      # Batas maksimal gelombang merambat (sesuai GDD)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var view_model: CanvasLayer = get_node_or_null("ViewModel")

var is_sprinting: bool = false
var is_flashlight_on: bool = false
var is_overheated: bool = false
var current_heat: float = 0.0
var overheat_timer: float = 0.0
var flicker_timer: float = 0.0
var is_flicker_dark: bool = false

# Variabel Kamera & Head Bob
var initial_camera_pos: Vector3 = Vector3.ZERO
var base_fov: float = 75.0
var bob_time: float = 0.0

# Variabel Gelombang Tap
var current_tap_radius: float = 0.0
var is_wave_active: bool = false

signal flashlight_exploded(player_position: Vector3)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	flashlight.visible = false
	initial_camera_pos = camera.position
	base_fov = camera.fov
	# Pastikan gelombang mati saat mulai
	RenderingServer.global_shader_parameter_set("tap_radius", 0.0)
	if view_model and view_model.has_method("update_flashlight_visual"):
		view_model.update_flashlight_visual(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	# Jika mouse sedang bebas, klik mouse akan menangkap kembali kursor
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		if event is InputEventMouseButton and event.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))
		
	# Nyalakan / Matikan Senter
	if event.is_action_pressed("toggle_flashlight") and not is_overheated:
		is_flashlight_on = !is_flashlight_on
		flashlight.visible = is_flashlight_on
		flashlight.light_energy = 1.0
		flicker_timer = 0.0
		is_flicker_dark = false
		if view_model and view_model.has_method("update_flashlight_visual"):
			view_model.update_flashlight_visual(is_flashlight_on)
		
	# Fitur Wall-Tap / Floor-Tap (Bisa dipakai saat gelap & gelombang sebelumnya sudah selesai)
	if event.is_action_pressed("wall_tap") and not is_flashlight_on and not is_wave_active:
		trigger_surface_tap()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	is_sprinting = Input.is_action_pressed("sprint") and direction.length() > 0.1
	var current_speed = SPRINT_SPEED if is_sprinting else WALK_SPEED
	
	var accel = ACCELERATION if is_on_floor() else AIR_ACCELERATION
	var decel = DECELERATION if is_on_floor() else AIR_DECELERATION

	if direction:
		velocity.x = move_toward(velocity.x, direction.x * current_speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)
		velocity.z = move_toward(velocity.z, 0.0, decel * delta)

	move_and_slide()
	handle_camera_dynamics(delta)
	handle_flashlight_heat(delta)
	handle_tap_wave(delta)

# Fungsi kontrol dinamika kamera (Head Bob & Dynamic Sprint FOV)
func handle_camera_dynamics(delta: float) -> void:
	# 1. Dynamic Sprint FOV
	var target_fov = SPRINT_FOV if is_sprinting else base_fov
	camera.fov = lerp(camera.fov, target_fov, FOV_TRANSITION_SPEED * delta)

	# 2. Procedural Head Bob
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal_speed > 0.1:
		var freq = BOB_FREQUENCY_SPRINT if is_sprinting else BOB_FREQUENCY_WALK
		var amp = BOB_AMPLITUDE_SPRINT if is_sprinting else BOB_AMPLITUDE_WALK
		bob_time += freq * delta
		camera.position.y = initial_camera_pos.y + sin(bob_time) * amp
		camera.position.x = initial_camera_pos.x + cos(bob_time * 0.5) * (amp * 0.5)
	else:
		bob_time = 0.0
		camera.position = camera.position.lerp(initial_camera_pos, BOB_RESET_SPEED * delta)

# Fungsi untuk menggerakkan cincin gelombang ke mesh-mesh sekitar
func handle_tap_wave(delta: float) -> void:
	if is_wave_active:
		current_tap_radius += TAP_WAVE_SPEED * delta
		RenderingServer.global_shader_parameter_set("tap_radius", current_tap_radius)
		
		if current_tap_radius >= TAP_MAX_RADIUS:
			is_wave_active = false
			current_tap_radius = 0.0
			RenderingServer.global_shader_parameter_set("tap_radius", 0.0)

# Fungsi mencari dinding/lantai terdekat untuk titik awal gelombang!
func trigger_surface_tap() -> void:
	var space_state = get_world_3d().direct_space_state
	var origin = camera.global_position
	
	# Daftar arah cek: 1. Arah pandangan mata, 2. Kanan, 3. Kiri, 4. Bawah (Lantai)
	var check_directions = [
		-camera.global_transform.basis.z * TAP_REACH_DISTANCE, # Depan
		camera.global_transform.basis.x * TAP_REACH_DISTANCE,  # Kanan
		-camera.global_transform.basis.x * TAP_REACH_DISTANCE, # Kiri
		Vector3(0, -2.5, 0)                                    # Lantai di bawah kaki
	]
	
	var closest_hit_pos: Vector3 = global_position - Vector3(0, 0.9, 0) # Default: titik kaki di lantai
	var min_dist: float = 999.0
	
	for dir in check_directions:
		var query = PhysicsRayQueryParameters3D.create(origin, origin + dir)
		query.exclude = [self.get_rid()] # Jangan mengetuk tubuh sendiri
		var result = space_state.intersect_ray(query)
		if result:
			var dist = origin.distance_to(result.position)
			if dist < min_dist:
				min_dist = dist
				closest_hit_pos = result.position
	
	# Mulai pancarkan gelombang dari titik dinding/lantai terdekat tersebut!
	RenderingServer.global_shader_parameter_set("tap_origin", closest_hit_pos)
	current_tap_radius = 0.05
	is_wave_active = true
	if view_model and view_model.has_method("play_tap_recoil"):
		view_model.play_tap_recoil()
	print("Tap! Gelombang merambat dari: ", closest_hit_pos)

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
		
		# 1. Critical Warning (heat >= CRITICAL_HEAT): Flicker intens & tidak beraturan (micro-blackout cepat)
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
		# 2. Heat Warning (heat >= WARNING_HEAT): Kedipan sesekali sebagai peringatan awal
		elif current_heat >= WARNING_HEAT:
			flicker_timer -= delta
			if flicker_timer <= 0.0:
				if is_flicker_dark:
					is_flicker_dark = false
					flashlight.visible = true
					flashlight.light_energy = 1.0
					flicker_timer = randf_range(WARNING_LIGHT_TIME_MIN, WARNING_LIGHT_TIME_MAX)
					if view_model and view_model.has_method("update_flashlight_visual"):
						view_model.update_flashlight_visual(true)
				else:
					is_flicker_dark = true
					flashlight.visible = false
					flashlight.light_energy = 0.0
					flicker_timer = randf_range(WARNING_DROP_TIME_MIN, WARNING_DROP_TIME_MAX)
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
