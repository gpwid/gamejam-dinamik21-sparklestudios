extends CharacterBody3D

# --- PENGATURAN GERAK ---
const WALK_SPEED = 3.0
const SPRINT_SPEED = 6.0
const MOUSE_SENSITIVITY = 0.003

# --- PENGATURAN SENTER OVERHEAT ---
const MAX_HEAT = 100.0
const HEAT_RATE = 15.0
const COOL_RATE = 20.0
const WARNING_HEAT = 70.0
const OVERHEAT_COOLDOWN = 4.0

# --- PENGATURAN GELOMBANG WALL-TAP ---
const TAP_REACH_DISTANCE = 3.0   # Jarak jangkauan tangan meraba dinding (meter)
const TAP_WAVE_SPEED = 2.2      # Kecepatan rambat gelombang (meter per detik)
const TAP_MAX_RADIUS = 8.0      # Batas maksimal gelombang merambat (sesuai GDD)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight

var is_sprinting: bool = false
var is_flashlight_on: bool = false
var is_overheated: bool = false
var current_heat: float = 0.0
var overheat_timer: float = 0.0

# Variabel Gelombang Tap
var current_tap_radius: float = 0.0
var is_wave_active: bool = false

signal flashlight_exploded(player_position: Vector3)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	flashlight.visible = false
	# Pastikan gelombang mati saat mulai
	RenderingServer.global_shader_parameter_set("tap_radius", 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	# Nyalakan / Matikan Senter
	if event.is_action_pressed("toggle_flashlight") and not is_overheated:
		is_flashlight_on = !is_flashlight_on
		flashlight.visible = is_flashlight_on
		flashlight.light_energy = 1.0
		
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
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	handle_flashlight_heat(delta)
	handle_tap_wave(delta)

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
	print("Tap! Gelombang merambat dari: ", closest_hit_pos)

func handle_flashlight_heat(delta: float) -> void:
	if is_overheated:
		overheat_timer -= delta
		if overheat_timer <= 0.0:
			is_overheated = false
			current_heat = 0.0
		return

	if is_flashlight_on:
		current_heat += HEAT_RATE * delta
		if current_heat >= WARNING_HEAT:
			flashlight.light_energy = randf_range(0.1, 1.2)
		else:
			flashlight.light_energy = 1.0
			
		if current_heat >= MAX_HEAT:
			is_overheated = true
			is_flashlight_on = false
			flashlight.visible = false
			overheat_timer = OVERHEAT_COOLDOWN
			emit_signal("flashlight_exploded", global_position)
	else:
		current_heat = move_toward(current_heat, 0.0, COOL_RATE * delta)
