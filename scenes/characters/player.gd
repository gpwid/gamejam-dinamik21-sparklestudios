extends CharacterBody3D

const WALK_SPEED = 3.0
const SPRINT_SPEED = 6.0
const MOUSE_SENSITIVITY = 0.003

# Mengambil referensi Kepala dan Senter
@onready var head: Node3D = $Head
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight

# Status pemain untuk dibaca oleh monster
var is_sprinting: bool = false
var is_flashlight_on: bool = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Mulai game dalam kondisi gelap
	flashlight.visible = false

func _unhandled_input(event: InputEvent) -> void:
	# Menggerakkan kepala/kamera dengan mouse
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		# Batasi agar leher tidak patah (maksimal nunduk/mendongak 80 derajat)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	
	# Tombol ESC untuk memunculkan kursor mouse kembali saat ngetes
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	# Nyalakan / Matikan Senter
	if event.is_action_pressed("toggle_flashlight"):
		is_flashlight_on = !is_flashlight_on
		flashlight.visible = is_flashlight_on

func _physics_process(delta: float) -> void:
	# Gravitasi agar pemain menapak lantai
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Cek apakah pemain menahan tombol Sprint (Shift)
	is_sprinting = Input.is_action_pressed("sprint")
	var current_speed = SPRINT_SPEED if is_sprinting else WALK_SPEED

	# Membaca tombol WASD sesuai Input Map yang kamu buat
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
