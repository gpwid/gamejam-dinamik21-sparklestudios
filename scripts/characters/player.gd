extends CharacterBody3D

const WALK_SPEED: float = 3.0
const SPRINT_SPEED: float = 6.0
const ACCELERATION: float = 25.0
const DECELERATION: float = 25.0
const AIR_CONTROL_FACTOR: float = 0.25
@export var mouse_sensitivity: float = 0.003
const MOUSE_SENSITIVITY: float = 0.003
const WALL_STOP_THRESHOLD: float = 0.82
const WALL_SLIDE_SPEED_MULT: float = 0.6
var is_sliding_on_wall: bool = false

const BOB_FREQUENCY_WALK: float = 10.0
const BOB_FREQUENCY_SPRINT: float = 14.0
const BOB_AMPLITUDE_WALK: float = 0.05
const BOB_AMPLITUDE_SPRINT: float = 0.08
const BOB_RESET_SPEED: float = 10.0

const BREATH_FREQUENCY: float = 0.685
const BREATH_AMPLITUDE_Y: float = 0.01
const BREATH_AMPLITUDE_X: float = 0.005

const SPRINT_FOV: float = 80.0
const FOV_TRANSITION_SPEED: float = 8.0

const STRAFE_TILT_ANGLE: float = deg_to_rad(1.8)
const TILT_SPEED: float = 7.0

const SPRING_STIFFNESS: float = 160.0
const SPRING_DAMPING: float = 15.0

const SWAY_AMOUNT: float = 0.0015
const SWAY_MAX: float = 0.15
const SWAY_RETURN_SPEED: float = 7.0
const SWAY_SMOOTH_SPEED: float = 11.0

@export_group("Flashlight Exposure Dynamics")
@export var max_exposure: float = 100.0
@export var exposure_increase_rate: float = 6.0
@export var normal_decrease_rate: float = 8.0
@export var triggered_cooldown_rate_off: float = 15.0
@export var triggered_cooldown_rate_on: float = 4.0
@export var overheated_spot_angle_multiplier: float = 0.45
@export var dim_start_threshold: float = 50.0
@export var flicker_start_threshold: float = 90.0
@export var base_light_energy: float = 1.0
@export var base_spot_angle: float = 45.0
@export var base_spot_range: float = 25.0
@export var auto_shutoff_threshold: float = 15.0
@export var penalty_lock_duration: float = 20.0

@export_group("Echolocation Dynamics")
@export var wall_reach_distance: float = 1.8
@export var wall_tap_max_radius: float = 17.0
@export var floor_tap_max_radius: float = 6.0
@export var wave_speed: float = 16.0
@export var wave_hold_duration: float = 0.35
@export var wave_fade_duration: float = 1.2
@export var tap_cooldown: float = 1.5
@export var double_ping_delay: float = 0.22

@export_group("Debug")
@export var debug_infinite_flashlight: bool = false

@export_group("Interaction")
@export var interact_distance: float = 2.5

@export_group("Audio Assets")
@export var footstep_sounds: Array[AudioStream] = []
@export var switch_sound: AudioStream
@export var echo_sound: AudioStream
@export var landing_sound: AudioStream
@export var trigger_scream_sound: AudioStream

@export_group("Heartbeat Audio")
@export var heartbeat_sound: AudioStream = preload("res://assets/audio/sfx/heartbeat.wav")
@export var max_heartbeat_distance: float = 15.0
@export var min_heartbeat_distance: float = 2.5
@export var slowest_beat_interval: float = 1.1
@export var fastest_beat_interval: float = 0.38
@export var min_heartbeat_volume_db: float = -10.0
@export var max_heartbeat_volume_db: float = 7.0
@export var min_heartbeat_pitch: float = 0.95
@export var max_heartbeat_pitch: float = 1.1

@export_group("Stamina Dynamics")
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 11.0
@export var hold_breath_drain_rate: float = 5.0
@export var stamina_recovery_rate: float = 18.0
@export var stamina_recovery_delay: float = 0.7
@export var exhausted_walk_speed: float = 1.8
@export var exhaustion_recovery_threshold: float = 25.0

@export_group("Breathing Audio Levels")
@export var idle_breath_volume_still: float = -14.0
@export var idle_breath_volume_moving: float = -18.0
@export var run_breath_start_vol: float = -14.0
@export var run_breath_max_vol: float = 1.0

var current_stamina: float = 100.0
var is_exhausted: bool = false
var stamina_recovery_timer: float = 0.0

var is_holding_breath: bool = false
var was_in_stealth_danger: bool = false
var was_closest_investigating: bool = false
var safe_hud_timer: float = 0.0
var lethal_zone_timer: float = 0.0
var is_in_warning_zone: bool = false
var fov_tween: Tween
var exhaustion_fade_tween: Tween
var cam_jolt_tween: Tween

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var footstep_player: AudioStreamPlayer3D = get_node_or_null("FootstepPlayer")
@onready var landing_player: AudioStreamPlayer3D = get_node_or_null("LandingPlayer")
@onready var flashlight_player: AudioStreamPlayer = get_node_or_null("FlashlightPlayer")
@onready var tap_echo_player: AudioStreamPlayer3D = get_node_or_null("TapEchoPlayer")
@onready var idle_breathing_player: AudioStreamPlayer = get_node_or_null("IdleBreathingPlayer")
@onready var running_breathing_player: AudioStreamPlayer = get_node_or_null("RunningBreathingPlayer")
@onready var exhaustion_player: AudioStreamPlayer = get_node_or_null("ExhaustionPlayer")
@onready var trigger_scream_player: AudioStreamPlayer = get_node_or_null("TriggerScreamPlayer")
@onready var heartbeat_player: AudioStreamPlayer = get_node_or_null("HeartbeatPlayer")
@onready var outline_pass: MeshInstance3D = get_node_or_null("Head/Camera3D/OutlinePass")
@onready var view_model: CanvasLayer = get_node_or_null("ViewModel")

var idle_breath_target_vol: float = -80.0
var running_breath_target_vol: float = -80.0
var outline_material: ShaderMaterial

var is_sprinting: bool = false
var was_on_floor: bool = true
var previous_vertical_velocity: float = 0.0

var is_flashlight_on: bool = false
var is_flashlight_locked: bool = false
var is_triggered: bool = false
var isTriggered: bool:
	get: return is_triggered
	set(val): is_triggered = val

var current_exposure: float = 0.0
var current_light_energy: float = 1.0
var current_spot_angle: float = 45.0
var flicker_timer: float = 0.0
var is_flicker_dark: bool = false
var has_triggered_scream: bool = false
var has_penalty_lock: bool = false
var penalty_lock_timer: float = 0.0
var mouse_input_accumulator: Vector2 = Vector2.ZERO
var sway_target: Vector3 = Vector3.ZERO

var beat_timer: float = 0.0
var current_beat_interval: float = 1.1

var is_overheated: bool:
	get: return is_triggered
	set(val): is_triggered = val

var current_heat: float:
	get: return current_exposure
	set(val): current_exposure = val

var max_heat: float:
	get: return max_exposure
	set(val): max_exposure = val

var heat_increase_rate: float:
	get: return exposure_increase_rate
	set(val): exposure_increase_rate = val

var heat_decrease_rate: float:
	get: return normal_decrease_rate
	set(val): normal_decrease_rate = val

var exposureIncreaseRate: float:
	get: return exposure_increase_rate
	set(val): exposure_increase_rate = val

var normalDecreaseRate: float:
	get: return normal_decrease_rate
	set(val): normal_decrease_rate = val

var triggeredCooldownRateOff: float:
	get: return triggered_cooldown_rate_off
	set(val): triggered_cooldown_rate_off = val

var triggeredCooldownRateOn: float:
	get: return triggered_cooldown_rate_on
	set(val): triggered_cooldown_rate_on = val

var overheated_light_multiplier: float:
	get: return overheated_spot_angle_multiplier
	set(val): overheated_spot_angle_multiplier = val

var overheatedLightMultiplier: float:
	get: return overheated_spot_angle_multiplier
	set(val): overheated_spot_angle_multiplier = val

var overheatedSpotAngleMultiplier: float:
	get: return overheated_spot_angle_multiplier
	set(val): overheated_spot_angle_multiplier = val

var dimStartThreshold: float:
	get: return dim_start_threshold
	set(val): dim_start_threshold = val

var flickerStartThreshold: float:
	get: return flicker_start_threshold
	set(val): flicker_start_threshold = val

var autoShutoffThreshold: float:
	get: return auto_shutoff_threshold
	set(val): auto_shutoff_threshold = val

var end_chase_lockout_threshold: float:
	get: return auto_shutoff_threshold
	set(val): auto_shutoff_threshold = val

var endChaseLockoutThreshold: float:
	get: return auto_shutoff_threshold
	set(val): auto_shutoff_threshold = val

var penaltyLockDuration: float:
	get: return penalty_lock_duration
	set(val): penalty_lock_duration = val

var end_chase_lockout_duration: float:
	get: return penalty_lock_duration
	set(val): penalty_lock_duration = val

var endChaseLockoutDuration: float:
	get: return penalty_lock_duration
	set(val): penalty_lock_duration = val

var initial_camera_pos: Vector3 = Vector3.ZERO
var base_fov: float = 75.0
var bob_time: float = 0.0
var breath_time: float = 0.0
var breath_motion_weight: float = 1.0
var sprint_audio_factor: float = 0.0
var current_bob_x: float = 0.0
var current_bob_y: float = 0.0
var current_roll_tilt: float = 0.0
var landing_spring_vel: float = 0.0
var landing_compression_y: float = 0.0
var is_step_triggered: bool = false

enum WavePhase { IDLE, EXPAND, HOLD, FADE }
var wave_phase: WavePhase = WavePhase.IDLE
var wave_timer: float = 0.0
var is_wave_active: bool = false
var current_tap_radius: float = 0.0
var shader_tap_radius: float = 0.0
var active_max_radius: float = 17.0
var tap_cooldown_timer: float = 0.0
var is_snapping: bool = false

signal flashlight_exploded(player_position: Vector3)
signal footstep_stepped(is_sprint: bool)
signal interaction_failed_in_dark()
signal echolocation_made(sound_origin: Vector3, radius: float)
signal onboarding_requested(type: String)

var has_shown_spawn_hint: bool = false
var has_shown_flashlight_hint: bool = false
var has_shown_switch_hint: bool = false
var has_shown_breath_hint: bool = false

var is_jumpscared: bool = false
var jumpscare_monster: Node3D = null

func _sync_outline_flashlight() -> void:
	if outline_material and flashlight:
		var min_allowed_spot_angle: float = base_spot_angle * overheated_spot_angle_multiplier
		var safe_spot_angle: float = clampf(flashlight.spot_angle, min_allowed_spot_angle, base_spot_angle)
		outline_material.set_shader_parameter("flashlight_cos_angle", cos(deg_to_rad(safe_spot_angle)))
		outline_material.set_shader_parameter("flashlight_range", flashlight.spot_range)
		outline_material.set_shader_parameter("flashlight_view_dir", -flashlight.transform.basis.z.normalized())
		outline_material.set_shader_parameter("flashlight_on", flashlight.visible and flashlight.spot_range > 0.1 and flashlight.light_energy > 0.0)

func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if flashlight:
		base_spot_angle = flashlight.spot_angle
		current_spot_angle = base_spot_angle
		base_spot_range = flashlight.spot_range
		flashlight.spot_angle_attenuation = 1.0
		flashlight.visible = false
		flashlight.light_energy = base_light_energy
		current_light_energy = base_light_energy
	initial_camera_pos = camera.position
	base_fov = camera.fov

	get_tree().create_timer(0.6).timeout.connect(func():
		if not has_shown_spawn_hint:
			has_shown_spawn_hint = true
			onboarding_requested.emit("spawn")
	)
	was_on_floor = is_on_floor()
	_set_tap_radius(0.0)
	_init_audio_fallbacks()
	_init_breathing_audio()

	if view_model and view_model.has_method("update_flashlight_visual"):
		view_model.update_flashlight_visual(false)
	if outline_pass:
		outline_pass.visible = true
		outline_material = outline_pass.get_active_material(0) as ShaderMaterial
		if outline_material and flashlight:
			outline_material.set_shader_parameter("flashlight_view_pos", flashlight.position)
			_sync_outline_flashlight()

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
	if trigger_scream_sound == null:
		trigger_scream_sound = load("res://assets/audio/sfx/trigger_scream.wav")
	if trigger_scream_player == null:
		trigger_scream_player = AudioStreamPlayer.new()
		trigger_scream_player.name = "TriggerScreamPlayer"
		add_child(trigger_scream_player)
	if trigger_scream_player.stream == null and trigger_scream_sound != null:
		trigger_scream_player.stream = trigger_scream_sound
	if heartbeat_sound == null:
		heartbeat_sound = load("res://assets/audio/sfx/heartbeat.wav")
	if heartbeat_player == null:
		heartbeat_player = AudioStreamPlayer.new()
		heartbeat_player.name = "HeartbeatPlayer"
		add_child(heartbeat_player)
	if heartbeat_player.stream == null and heartbeat_sound != null:
		heartbeat_player.stream = heartbeat_sound

func _unhandled_input(event: InputEvent) -> void:
	if is_jumpscared:
		return

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mouse_x: float = event.relative.x
		var mouse_y: float = event.relative.y

		rotate_y(-mouse_x * mouse_sensitivity)
		head.rotate_x(-mouse_y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))

		mouse_input_accumulator.x += mouse_x
		mouse_input_accumulator.y += mouse_y

	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		debug_infinite_flashlight = !debug_infinite_flashlight
		if debug_infinite_flashlight:
			is_triggered = false
			has_triggered_scream = false
			current_exposure = 0.0
			if view_model:
				if view_model.has_method("update_flashlight_visual"):
					view_model.update_flashlight_visual(is_flashlight_on)
				if view_model.has_method("play_overheat_warning"):
					view_model.play_overheat_warning(false)
		print("[debug] infinite flashlight: ", debug_infinite_flashlight)

	if event.is_action_pressed("toggle_flashlight") and not event.is_echo():
		toggle_flashlight()

	if event.is_action_pressed("wall_tap") and not is_flashlight_on and not is_wave_active and not is_snapping and tap_cooldown_timer <= 0.0:
		if view_model and view_model.has_method("play_snap_animation"):
			is_snapping = true
			view_model.play_snap_animation(
				func(): trigger_surface_tap(),
				func(): is_snapping = false
			)
		else:
			trigger_surface_tap()

	if event.is_action_pressed("interact"):
		try_interact()

func toggle_flashlight() -> void:
	if is_flashlight_locked or penalty_lock_timer > 0.0:
		if penalty_lock_timer > 0.0:
			print("[flashlight] locked, penalty: %ss" % snapped(penalty_lock_timer, 0.1))
		else:
			print("[flashlight] locked at end of chase")
		if flashlight_player:
			flashlight_player.pitch_scale = 0.7
			if switch_sound:
				flashlight_player.stream = switch_sound
			if flashlight_player.stream:
				flashlight_player.play()
		return

	if view_model and view_model.has_method("play_flashlight_click"):
		view_model.play_flashlight_click()

	if flashlight_player:
		flashlight_player.pitch_scale = randf_range(0.95, 1.05)
		if switch_sound:
			flashlight_player.stream = switch_sound
		if flashlight_player.stream:
			flashlight_player.play()

	is_flashlight_on = !is_flashlight_on
	flashlight.visible = is_flashlight_on
	flicker_timer = 0.0
	is_flicker_dark = false

	if is_flashlight_on:
		flashlight.spot_range = base_spot_range
		flashlight.light_energy = base_light_energy
		current_light_energy = base_light_energy
		if is_triggered:
			current_spot_angle = base_spot_angle * overheated_spot_angle_multiplier
			flashlight.spot_angle = current_spot_angle
		else:
			if current_exposure >= flicker_start_threshold:
				current_spot_angle = base_spot_angle * overheated_spot_angle_multiplier
			elif current_exposure > dim_start_threshold:
				var t: float = clampf((current_exposure - dim_start_threshold) / (flicker_start_threshold - dim_start_threshold), 0.0, 1.0)
				current_spot_angle = lerpf(base_spot_angle, base_spot_angle * overheated_spot_angle_multiplier, t)
			else:
				current_spot_angle = base_spot_angle
			flashlight.spot_angle = current_spot_angle
	else:
		current_light_energy = 0.0
		flashlight.light_energy = 0.0
		flashlight.spot_range = base_spot_range
		current_spot_angle = base_spot_angle
		flashlight.spot_angle = base_spot_angle

	_sync_outline_flashlight()

	if view_model:
		if view_model.has_method("update_flashlight_visual"):
			view_model.update_flashlight_visual(is_flashlight_on)
		if view_model.has_method("play_overheat_warning"):
			view_model.play_overheat_warning(is_triggered)
		if view_model.has_method("update_flashlight_heat"):
			view_model.update_flashlight_heat(current_exposure, max_exposure, is_flashlight_on, is_triggered)

func _process(delta: float) -> void:
	handle_heartbeat_audio(delta)

func _physics_process(delta: float) -> void:
	if is_jumpscared:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		if is_instance_valid(jumpscare_monster):
			var look_target: Vector3 = jumpscare_monster.get_head_global_position() if jumpscare_monster.has_method("get_head_global_position") else (jumpscare_monster.global_position + Vector3(0.0, 2.35, 0.0))
			var cam_pos := head.to_global(initial_camera_pos)
			var target_dir := (look_target - cam_pos).normalized()
			if target_dir.length() > 0.01:
				var target_yaw := atan2(-target_dir.x, -target_dir.z)
				var target_pitch := asin(clampf(target_dir.y, -0.99, 0.99))
				global_rotation.y = lerp_angle(global_rotation.y, target_yaw, 24.0 * delta)
				head.rotation.x = lerp_angle(head.rotation.x, target_pitch, 24.0 * delta)
				camera.fov = lerpf(camera.fov, 54.0, 14.0 * delta)
				camera.position = initial_camera_pos + Vector3(randf_range(-0.035, 0.035), randf_range(-0.035, 0.035), 0.0)
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var is_moving_intent: bool = direction.length() > 0.1 and not is_sliding_on_wall
	var wants_to_sprint: bool = Input.is_action_pressed("sprint") and is_moving_intent
	if wants_to_sprint and not is_exhausted and current_stamina > 0.0:
		is_sprinting = true
	else:
		is_sprinting = false

	# hold breath with shift when standing still
	var wants_to_hold_breath: bool = Input.is_action_pressed("sprint") and not is_moving_intent and not is_exhausted and current_stamina > 0.0
	if wants_to_hold_breath:
		if not is_holding_breath:
			_start_holding_breath()
	else:
		if is_holding_breath:
			_stop_holding_breath()

	var current_speed: float = WALK_SPEED
	if is_sprinting:
		current_speed = SPRINT_SPEED
	elif is_exhausted:
		current_speed = exhausted_walk_speed

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

	is_sliding_on_wall = false
	var real_vel := get_real_velocity()
	var horizontal_speed: float = Vector2(real_vel.x, real_vel.z).length()

	if is_on_wall() and direction.length() > 0.1:
		var wall_normal_h := Vector3(get_wall_normal().x, 0.0, get_wall_normal().z).normalized()
		var into_wall_dot: float = -direction.dot(wall_normal_h)

		if into_wall_dot >= WALL_STOP_THRESHOLD:
			velocity.x = 0.0
			velocity.z = 0.0
			horizontal_speed = 0.0
			is_sprinting = false
		elif into_wall_dot > 0.1:
			is_sliding_on_wall = true
			is_sprinting = false
			var max_slide_speed: float = WALK_SPEED * WALL_SLIDE_SPEED_MULT
			var h_vel := Vector2(velocity.x, velocity.z)
			if h_vel.length() > max_slide_speed:
				h_vel = h_vel.normalized() * max_slide_speed
				velocity.x = h_vel.x
				velocity.z = h_vel.y
			horizontal_speed = minf(horizontal_speed, max_slide_speed)

	if is_on_floor() and horizontal_speed < 0.2:
		is_sprinting = false

	handle_camera_immersion(delta, input_dir, horizontal_speed)
	update_flashlight_sway(delta)
	handle_flashlight_heat(delta)
	handle_tap_wave(delta)
	handle_stamina(delta, horizontal_speed > 0.2)
	handle_breathing_audio(delta, horizontal_speed > 0.2)
	handle_monster_proximity_zones(delta, horizontal_speed)

	_sync_outline_flashlight()

func handle_camera_immersion(delta: float, input_dir: Vector2, horizontal_speed: float) -> void:
	if not is_holding_breath and (fov_tween == null or not fov_tween.is_valid()):
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
	var is_moving: bool = horizontal_speed > 0.1
	var is_grounded_moving: bool = is_on_floor() and is_moving
	var is_idle: bool = not is_moving

	if is_grounded_moving:
		var freq: float = BOB_FREQUENCY_SPRINT if is_sprinting else BOB_FREQUENCY_WALK
		var amp: float = BOB_AMPLITUDE_SPRINT if is_sprinting else BOB_AMPLITUDE_WALK

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
	var target_breath_weight: float = 1.0 if is_idle else 0.0
	breath_motion_weight = lerpf(breath_motion_weight, target_breath_weight, clampf(5.0 * delta, 0.0, 1.0))
	breath_offset.y = sin(breath_time) * BREATH_AMPLITUDE_Y * breath_motion_weight
	breath_offset.x = cos(breath_time * 0.5) * BREATH_AMPLITUDE_X * breath_motion_weight

	if view_model:
		if view_model.has_method("update_movement"):
			view_model.update_movement(is_grounded_moving, is_sprinting, horizontal_speed, delta)
		elif view_model.has_method("set_idle"):
			view_model.set_idle(is_idle)

	camera.position = initial_camera_pos + bob_offset + breath_offset + Vector3(0.0, landing_compression_y, 0.0)
	_update_interact_hover()

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

func _trigger_landing(_impact_vel: float) -> void:
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

func handle_flashlight_heat(delta: float) -> void:
	handle_flashlight_exposure(delta)

func handle_flashlight_exposure(delta: float) -> void:
	var min_allowed_spot_angle: float = base_spot_angle * overheated_spot_angle_multiplier
	if penalty_lock_timer > 0.0:
		penalty_lock_timer = maxf(0.0, penalty_lock_timer - delta)
		if penalty_lock_timer <= 0.0 and not is_triggered:
			is_flashlight_locked = false
			has_penalty_lock = false
			print("[flashlight] penalty lock expired")

	if debug_infinite_flashlight:
		if is_triggered:
			is_triggered = false
			has_triggered_scream = false
		current_exposure = 0.0
		is_flicker_dark = false
		is_flashlight_locked = false
		has_penalty_lock = false
		penalty_lock_timer = 0.0
		flicker_timer = 0.0
		flashlight.visible = is_flashlight_on
		flashlight.light_energy = base_light_energy if is_flashlight_on else 0.0
		current_light_energy = flashlight.light_energy
		flashlight.spot_range = base_spot_range
		flashlight.spot_angle = base_spot_angle
		current_spot_angle = base_spot_angle
		_sync_outline_flashlight()
		if view_model:
			if view_model.has_method("update_flashlight_visual"):
				view_model.update_flashlight_visual(is_flashlight_on)
			if view_model.has_method("play_overheat_warning"):
				view_model.play_overheat_warning(false)
		return

	if is_triggered:
		if current_exposure <= auto_shutoff_threshold:
			if is_flashlight_on:
				is_flashlight_on = false
				flashlight.visible = false
				current_light_energy = 0.0
				flashlight.light_energy = 0.0
				flashlight.spot_range = base_spot_range
				has_penalty_lock = true
				penalty_lock_timer = penalty_lock_duration
				is_flashlight_locked = true
				if view_model and view_model.has_method("update_flashlight_visual"):
					view_model.update_flashlight_visual(false)
				print("[flashlight] auto shutoff at %s%%" % snapped(current_exposure, 0.1))

			is_flashlight_locked = true
			current_exposure = move_toward(current_exposure, 0.0, triggered_cooldown_rate_off * delta)
		else:
			if is_flashlight_on:
				current_exposure = move_toward(current_exposure, 0.0, triggered_cooldown_rate_on * delta)
				if current_exposure <= auto_shutoff_threshold:
					is_flashlight_on = false
					flashlight.visible = false
					current_light_energy = 0.0
					flashlight.light_energy = 0.0
					flashlight.spot_range = base_spot_range
					has_penalty_lock = true
					penalty_lock_timer = penalty_lock_duration
					is_flashlight_locked = true
					if view_model and view_model.has_method("update_flashlight_visual"):
						view_model.update_flashlight_visual(false)
					print("[flashlight] auto shutoff at %s%%" % snapped(current_exposure, 0.1))
				else:
					var target_angle: float = base_spot_angle * overheated_spot_angle_multiplier
					current_spot_angle = target_angle
					flashlight.spot_angle = current_spot_angle
					flashlight.spot_range = base_spot_range
					flashlight.visible = true
					flashlight.light_energy = base_light_energy
					current_light_energy = base_light_energy
			else:
				current_exposure = move_toward(current_exposure, 0.0, triggered_cooldown_rate_off * delta)
				flashlight.visible = false
				flashlight.light_energy = 0.0
				current_light_energy = 0.0
				flashlight.spot_range = base_spot_range
				if current_exposure <= auto_shutoff_threshold:
					is_flashlight_locked = true

		if current_exposure <= 0.0:
			current_exposure = 0.0
			is_triggered = false
			has_triggered_scream = false
			current_spot_angle = base_spot_angle
			flashlight.spot_angle = base_spot_angle
			flashlight.spot_range = base_spot_range
			current_light_energy = base_light_energy
			flashlight.light_energy = base_light_energy

			if has_penalty_lock:
				is_flashlight_locked = true
			else:
				is_flashlight_locked = false

			if view_model and view_model.has_method("play_overheat_warning"):
				view_model.play_overheat_warning(false)

		min_allowed_spot_angle = base_spot_angle * overheated_spot_angle_multiplier
		flashlight.spot_angle = clampf(flashlight.spot_angle, min_allowed_spot_angle, base_spot_angle)
		current_spot_angle = clampf(current_spot_angle, min_allowed_spot_angle, base_spot_angle)
		flashlight.light_energy = clampf(flashlight.light_energy, 0.0, base_light_energy)
		current_light_energy = clampf(current_light_energy, 0.0, base_light_energy)
		flashlight.spot_range = clampf(flashlight.spot_range, 0.0, base_spot_range)

		_sync_outline_flashlight()

		if view_model and view_model.has_method("update_flashlight_heat"):
			view_model.update_flashlight_heat(current_exposure, max_exposure, is_flashlight_on, is_triggered)
		return

	if is_flashlight_on:
		current_exposure = minf(max_exposure, current_exposure + exposure_increase_rate * delta)

		if current_exposure < dim_start_threshold:
			current_spot_angle = base_spot_angle
			flashlight.spot_angle = base_spot_angle
			flashlight.spot_range = base_spot_range
			flashlight.visible = true
			flashlight.light_energy = base_light_energy
			current_light_energy = base_light_energy
			is_flicker_dark = false
			flicker_timer = 0.0

		elif current_exposure < flicker_start_threshold:
			var progress: float = clampf((current_exposure - dim_start_threshold) / (flicker_start_threshold - dim_start_threshold), 0.0, 1.0)
			var min_spot_angle: float = base_spot_angle * overheated_spot_angle_multiplier
			current_spot_angle = lerpf(base_spot_angle, min_spot_angle, progress)
			flashlight.spot_angle = current_spot_angle
			flashlight.spot_range = base_spot_range
			flashlight.visible = true
			flashlight.light_energy = base_light_energy
			current_light_energy = base_light_energy
			is_flicker_dark = false
			flicker_timer = 0.0

		else:
			var min_spot_angle: float = base_spot_angle * overheated_spot_angle_multiplier
			current_spot_angle = min_spot_angle
			flashlight.spot_angle = min_spot_angle

			flicker_timer -= delta
			if flicker_timer <= 0.0:
				is_flicker_dark = !is_flicker_dark
				if is_flicker_dark:
					flicker_timer = randf_range(0.04, 0.09)
				else:
					flicker_timer = randf_range(0.06, 0.14)

			if is_flicker_dark:
				flashlight.spot_range = 0.0
				flashlight.light_energy = 0.0
				flashlight.visible = false
				current_light_energy = 0.0
			else:
				flashlight.spot_range = base_spot_range
				flashlight.light_energy = base_light_energy
				flashlight.visible = true
				current_light_energy = base_light_energy

		if current_exposure >= max_exposure:
			_trigger_overheat()
	else:
		current_exposure = move_toward(current_exposure, 0.0, normal_decrease_rate * delta)
		is_flicker_dark = false
		flashlight.visible = false
		flashlight.light_energy = 0.0
		current_light_energy = 0.0
		flashlight.spot_range = base_spot_range
		current_spot_angle = base_spot_angle
		flashlight.spot_angle = base_spot_angle
		flicker_timer = 0.0
		if view_model and view_model.has_method("update_flashlight_visual"):
			view_model.update_flashlight_visual(false)

	min_allowed_spot_angle = base_spot_angle * overheated_spot_angle_multiplier
	flashlight.spot_angle = clampf(flashlight.spot_angle, min_allowed_spot_angle, base_spot_angle)
	current_spot_angle = clampf(current_spot_angle, min_allowed_spot_angle, base_spot_angle)
	flashlight.light_energy = clampf(flashlight.light_energy, 0.0, base_light_energy)
	current_light_energy = clampf(current_light_energy, 0.0, base_light_energy)
	flashlight.spot_range = clampf(flashlight.spot_range, 0.0, base_spot_range)

	_sync_outline_flashlight()

	if view_model and view_model.has_method("update_flashlight_heat"):
		view_model.update_flashlight_heat(current_exposure, max_exposure, is_flashlight_on, is_triggered)

func _trigger_overheat() -> void:
	current_exposure = max_exposure
	is_triggered = true
	has_penalty_lock = false
	penalty_lock_timer = 0.0
	is_flashlight_locked = false

	is_flashlight_on = false
	flashlight.visible = false
	flashlight.light_energy = 0.0
	current_light_energy = 0.0
	flashlight.spot_range = base_spot_range
	is_flicker_dark = false
	flicker_timer = 0.0
	current_spot_angle = base_spot_angle * overheated_spot_angle_multiplier
	flashlight.spot_angle = current_spot_angle
	print("[flashlight] overheat triggered")

	if not has_triggered_scream:
		has_triggered_scream = true
		if trigger_scream_player:
			if trigger_scream_player.stream == null and trigger_scream_sound != null:
				trigger_scream_player.stream = trigger_scream_sound
			if trigger_scream_player.stream:
				trigger_scream_player.play()

	_sync_outline_flashlight()

	if view_model:
		if view_model.has_method("update_flashlight_visual"):
			view_model.update_flashlight_visual(false)
		if view_model.has_method("play_overheat_warning"):
			view_model.play_overheat_warning(true)
		if view_model.has_method("update_flashlight_heat"):
			view_model.update_flashlight_heat(current_exposure, max_exposure, false, true)
	emit_signal("flashlight_exploded", global_position if is_inside_tree() else position)

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
			var can_dark: bool = false
			if interact_target.has_method("can_interact_in_dark"):
				can_dark = interact_target.can_interact_in_dark()
			elif interact_target.is_in_group("interact_in_dark"):
				can_dark = true

			if (is_flashlight_on and flashlight.visible and flashlight.light_energy > 0.05) or can_dark:
				if interact_target.has_method("interact"):
					interact_target.interact(self)
			else:
				interaction_failed_in_dark.emit()
				landing_spring_vel -= 0.7
				if interact_target.has_method("interact_in_dark"):
					interact_target.interact_in_dark(self)

func _update_interact_hover() -> void:
	if camera == null:
		return
	var space_state := get_world_3d().direct_space_state
	var cam_from := camera.global_position
	var cam_to := cam_from + (-camera.global_transform.basis.z * interact_distance)

	var query := PhysicsRayQueryParameters3D.create(cam_from, cam_to)
	query.exclude = [self.get_rid()]
	var result := space_state.intersect_ray(query)

	var is_hovering: bool = false
	if result and result.has("collider") and result.collider:
		var target: Node = result.collider
		var interact_target: Node = target
		if not (interact_target.has_method("interact") or interact_target.is_in_group("interactable")):
			if target.get_parent() and (target.get_parent().has_method("interact") or target.get_parent().is_in_group("interactable")):
				interact_target = target.get_parent()
			elif target.owner and (target.owner.has_method("interact") or target.owner.is_in_group("interactable")):
				interact_target = target.owner

		if interact_target.has_method("interact") or interact_target.is_in_group("interactable"):
			is_hovering = true
			if interact_target.is_in_group("switch") and not has_shown_switch_hint:
				has_shown_switch_hint = true
				onboarding_requested.emit("switch")

	if view_model and view_model.has_method("set_interactable_hover"):
		view_model.set_interactable_hover(is_hovering)

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

	if not hit_wall:
		var floor_query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(0.0, -2.5, 0.0))
		floor_query.exclude = [self.get_rid()]
		var floor_res: Dictionary = space_state.intersect_ray(floor_query)
		if floor_res:
			closest_hit_pos = floor_res.position

	active_max_radius = wall_tap_max_radius if hit_wall else floor_tap_max_radius

	RenderingServer.global_shader_parameter_set("tap_origin", closest_hit_pos)
	echolocation_made.emit(closest_hit_pos, active_max_radius)

	if not has_shown_flashlight_hint:
		has_shown_flashlight_hint = true
		get_tree().create_timer(1.2).timeout.connect(func():
			onboarding_requested.emit("flashlight")
		)

	_set_tap_radius(0.0)
	current_tap_radius = 0.0
	wave_timer = 0.0
	wave_phase = WavePhase.EXPAND
	is_wave_active = true
	tap_cooldown_timer = 0.0

	if tap_echo_player:
		tap_echo_player.global_position = closest_hit_pos
		if echo_sound:
			tap_echo_player.stream = echo_sound
		if tap_echo_player.stream:
			tap_echo_player.pitch_scale = 1.0 if hit_wall else 0.82
			tap_echo_player.volume_db = 0.0 if hit_wall else -5.0
			tap_echo_player.play()

	if hit_wall:
		get_tree().create_timer(double_ping_delay).timeout.connect(func():
			if is_instance_valid(tap_echo_player) and tap_echo_player.stream:
				tap_echo_player.pitch_scale = randf_range(0.96, 1.04)
				tap_echo_player.play()
		)

	if view_model and view_model.has_method("play_tap_recoil"):
		view_model.play_tap_recoil()

	print("[echolocation] tap: ", "wall" if hit_wall else "floor")

func _init_breathing_audio() -> void:
	if idle_breathing_player:
		idle_breathing_player.volume_db = -80.0
		idle_breathing_player.finished.connect(func():
			if is_instance_valid(idle_breathing_player):
				idle_breathing_player.play()
		)
		idle_breathing_player.play()

	if running_breathing_player:
		running_breathing_player.volume_db = -80.0
		running_breathing_player.finished.connect(func():
			if is_instance_valid(running_breathing_player):
				running_breathing_player.play()
		)
		running_breathing_player.play()

func _start_holding_breath() -> void:
	if is_holding_breath:
		return
	is_holding_breath = true
	lethal_zone_timer = 0.0
	if fov_tween and fov_tween.is_valid():
		fov_tween.kill()
	fov_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fov_tween.tween_property(camera, "fov", base_fov - 5.0, 0.28)
	if view_model:
		if view_model.has_method("set_holding_breath"):
			view_model.set_holding_breath(true, current_stamina / max_stamina)
		if view_model.has_method("update_stealth_hud"):
			if is_in_warning_zone:
				view_model.update_stealth_hud(2, current_stamina / max_stamina)
			else:
				view_model.update_stealth_hud(4, current_stamina / max_stamina)

func _stop_holding_breath() -> void:
	if not is_holding_breath:
		return
	is_holding_breath = false
	if fov_tween and fov_tween.is_valid():
		fov_tween.kill()
	fov_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fov_tween.tween_property(camera, "fov", base_fov, 0.35)
	if view_model:
		if view_model.has_method("set_holding_breath"):
			view_model.set_holding_breath(false, current_stamina / max_stamina)
		if view_model.has_method("update_stealth_hud"):
			if safe_hud_timer > 0.0:
				view_model.update_stealth_hud(3)
			elif is_in_warning_zone:
				view_model.update_stealth_hud(1)
			else:
				view_model.update_stealth_hud(0)

func handle_stamina(delta: float, is_moving: bool) -> void:
	if is_sprinting and is_moving:
		stamina_recovery_timer = stamina_recovery_delay
		current_stamina = maxf(0.0, current_stamina - stamina_drain_rate * delta)
		if current_stamina <= 0.0 and not is_exhausted:
			_trigger_exhaustion()
	elif is_holding_breath:
		stamina_recovery_timer = stamina_recovery_delay
		current_stamina = maxf(0.0, current_stamina - hold_breath_drain_rate * delta)
		if current_stamina <= 0.0 and not is_exhausted:
			_trigger_exhaustion()
	else:
		if stamina_recovery_timer > 0.0:
			stamina_recovery_timer -= delta
		else:
			current_stamina = minf(max_stamina, current_stamina + stamina_recovery_rate * delta)

		if is_exhausted and current_stamina >= exhaustion_recovery_threshold:
			_clear_exhaustion()

	if view_model:
		if view_model.has_method("set_holding_breath"):
			view_model.set_holding_breath(is_holding_breath, current_stamina / max_stamina)
		if view_model.has_method("update_stamina_blur"):
			view_model.update_stamina_blur(current_stamina, max_stamina, is_exhausted)

func _trigger_exhaustion() -> void:
	is_exhausted = true
	is_sprinting = false
	if is_holding_breath:
		_stop_holding_breath()

	running_breath_target_vol = -80.0
	if running_breathing_player:
		running_breathing_player.stop()
		running_breathing_player.volume_db = -80.0
	if idle_breathing_player:
		idle_breathing_player.stop()
		idle_breathing_player.volume_db = -80.0

	if exhaustion_player:
		if exhaustion_fade_tween and exhaustion_fade_tween.is_valid():
			exhaustion_fade_tween.kill()
		exhaustion_player.volume_db = 0.0
		exhaustion_player.pitch_scale = randf_range(0.97, 1.03)
		exhaustion_player.play(0.0)

		exhaustion_fade_tween = create_tween()
		exhaustion_fade_tween.tween_interval(3.5)
		exhaustion_fade_tween.tween_property(exhaustion_player, "volume_db", -80.0, 0.8)
		exhaustion_fade_tween.tween_callback(func():
			if is_instance_valid(exhaustion_player) and exhaustion_player.playing:
				exhaustion_player.stop()
		)

	if cam_jolt_tween and cam_jolt_tween.is_valid():
		cam_jolt_tween.kill()
	var base_cam_rot_x: float = camera.rotation.x
	cam_jolt_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cam_jolt_tween.tween_property(camera, "rotation:x", base_cam_rot_x - deg_to_rad(3.5), 0.12)
	cam_jolt_tween.tween_property(camera, "rotation:x", base_cam_rot_x, 0.35).set_trans(Tween.TRANS_SINE)

	if view_model and view_model.has_method("play_exhaustion_jolt"):
		view_model.play_exhaustion_jolt()

	if view_model:
		if view_model.has_method("update_stamina_blur"):
			view_model.update_stamina_blur(0.0, max_stamina, true)
		elif view_model.has_method("set_exhausted"):
			view_model.set_exhausted(true)

	var closest_monster: Node3D = _get_closest_monster()
	if closest_monster != null and is_inside_tree():
		var dist_to_m: float = global_position.distance_to(closest_monster.global_position)
		var wall_blocked: bool = is_wall_blocking_to_monster(closest_monster)
		if (not wall_blocked and dist_to_m < 6.0) or (wall_blocked and dist_to_m < 2.5):
			if closest_monster.has_method("trigger_close_gasp_chase"):
				closest_monster.trigger_close_gasp_chase()

	print("[player] exhausted")

func _clear_exhaustion() -> void:
	is_exhausted = false
	if view_model:
		if view_model.has_method("update_stamina_blur"):
			view_model.update_stamina_blur(current_stamina, max_stamina, false)
		elif view_model.has_method("set_exhausted"):
			view_model.set_exhausted(false)

	if exhaustion_player and exhaustion_player.playing:
		if exhaustion_fade_tween and exhaustion_fade_tween.is_valid():
			exhaustion_fade_tween.kill()
		exhaustion_fade_tween = create_tween()
		exhaustion_fade_tween.tween_property(exhaustion_player, "volume_db", -80.0, 0.4)
		exhaustion_fade_tween.tween_callback(func():
			if is_instance_valid(exhaustion_player) and exhaustion_player.playing:
				exhaustion_player.stop()
		)

	print("[player] stamina recovered")

func handle_breathing_audio(delta: float, is_moving: bool) -> void:
	if is_holding_breath:
		running_breath_target_vol = -80.0
		idle_breath_target_vol = -80.0
		if running_breathing_player and running_breathing_player.playing:
			running_breathing_player.stop()
		if idle_breathing_player and idle_breathing_player.playing:
			idle_breathing_player.stop()
		return

	if is_sprinting:
		sprint_audio_factor = minf(1.0, sprint_audio_factor + 3.0 * delta)
		if running_breathing_player and not running_breathing_player.playing:
			running_breathing_player.volume_db = -60.0
			running_breathing_player.play()

		var drain_ratio: float = 1.0 - clampf(current_stamina / max_stamina, 0.0, 1.0)
		var target_run_vol: float = lerpf(run_breath_start_vol, run_breath_max_vol, drain_ratio)
		running_breath_target_vol = lerpf(-60.0, target_run_vol, sprint_audio_factor)
		if running_breathing_player:
			running_breathing_player.pitch_scale = lerpf(0.98, 1.08, drain_ratio)

		idle_breath_target_vol = lerpf(idle_breath_volume_moving, -80.0, sprint_audio_factor)

	elif is_exhausted:
		sprint_audio_factor = maxf(0.0, sprint_audio_factor - 3.0 * delta)
		running_breath_target_vol = -80.0
		if running_breathing_player and running_breathing_player.playing:
			running_breathing_player.stop()

		if exhaustion_player and exhaustion_player.playing:
			idle_breath_target_vol = -80.0
		else:
			if idle_breathing_player and not idle_breathing_player.playing:
				idle_breathing_player.volume_db = -80.0
				idle_breathing_player.play()
			var recovery_progress: float = clampf(current_stamina / exhaustion_recovery_threshold, 0.0, 1.0)
			idle_breath_target_vol = lerpf(-26.0, idle_breath_volume_still, recovery_progress)

	else:
		sprint_audio_factor = maxf(0.0, sprint_audio_factor - 3.0 * delta)
		running_breath_target_vol = -80.0
		if running_breathing_player and running_breathing_player.volume_db <= -70.0 and running_breathing_player.playing:
			running_breathing_player.stop()

		if idle_breathing_player and not idle_breathing_player.playing:
			idle_breathing_player.volume_db = -80.0
			idle_breathing_player.play()

		var calm_target: float = idle_breath_volume_still if not is_moving else idle_breath_volume_moving
		idle_breath_target_vol = lerpf(calm_target, -80.0, sprint_audio_factor)

	if idle_breathing_player:
		idle_breathing_player.volume_db = lerpf(idle_breathing_player.volume_db, idle_breath_target_vol, clampf(4.0 * delta, 0.0, 1.0))
	if running_breathing_player:
		running_breathing_player.volume_db = lerpf(running_breathing_player.volume_db, running_breath_target_vol, clampf(4.0 * delta, 0.0, 1.0))

func is_wall_blocking_to_monster(closest_monster: Node3D) -> bool:
	if closest_monster == null or not is_inside_tree():
		return true
	var world_3d := get_world_3d()
	if world_3d == null:
		return true
	var space_state := world_3d.direct_space_state
	if space_state == null:
		return true

	var from_pos: Vector3 = camera.global_position if camera else (global_position + Vector3(0.0, 1.4, 0.0))
	var to_pos: Vector3 = closest_monster.global_position + Vector3(0.0, 1.4, 0.0)

	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excludes: Array[RID] = [get_rid()]
	if closest_monster is CollisionObject3D:
		excludes.append((closest_monster as CollisionObject3D).get_rid())
	query.exclude = excludes

	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	if hit.collider is StaticBody3D or hit.collider is CSGBox3D:
		return true
	return false

func handle_monster_proximity_zones(delta: float, horizontal_speed: float) -> void:
	if is_jumpscared:
		return

	var closest_monster: Node3D = _get_closest_monster()
	if closest_monster == null or not is_inside_tree():
		was_closest_investigating = false
		if is_in_warning_zone:
			is_in_warning_zone = false
			if view_model and view_model.has_method("set_warning_zone"):
				view_model.set_warning_zone(false, 0.0)
		if was_in_stealth_danger:
			was_in_stealth_danger = false
			safe_hud_timer = 1.8

		if safe_hud_timer > 0.0:
			safe_hud_timer -= delta

		if view_model and view_model.has_method("update_stealth_hud"):
			if is_holding_breath:
				view_model.update_stealth_hud(4, current_stamina / max_stamina)
			elif safe_hud_timer > 0.0:
				view_model.update_stealth_hud(3)
			else:
				view_model.update_stealth_hud(0)
		lethal_zone_timer = 0.0
		return

	var dist: float = global_position.distance_to(closest_monster.global_position)
	var is_wall_blocked: bool = is_wall_blocking_to_monster(closest_monster)
	var is_monster_investigating: bool = closest_monster != null and "current_state" in closest_monster and closest_monster.current_state == 1

	if was_closest_investigating and not is_monster_investigating:
		safe_hud_timer = 1.8
		was_in_stealth_danger = false
	was_closest_investigating = is_monster_investigating

	var danger_dist_thresh: float = 9.0 if is_in_warning_zone else 8.5
	var is_danger_active: bool = (dist <= danger_dist_thresh and not is_wall_blocked) or (dist < 1.8) or (is_monster_investigating and dist <= 11.0)

	if is_danger_active:
		was_in_stealth_danger = true
		is_in_warning_zone = true
		safe_hud_timer = 0.0
		var fear_intensity: float = clampf((9.0 - dist) / 4.5, 0.25, 1.0)
		if view_model and view_model.has_method("set_warning_zone"):
			view_model.set_warning_zone(true, fear_intensity)

		if view_model and view_model.has_method("update_stealth_hud"):
			if is_holding_breath:
				view_model.update_stealth_hud(2, current_stamina / max_stamina)
			else:
				view_model.update_stealth_hud(1)
				if not has_shown_breath_hint:
					has_shown_breath_hint = true
					onboarding_requested.emit("breath")

		if is_flashlight_on and flashlight and not is_triggered:
			if randf() < 0.22:
				flashlight.light_energy = base_light_energy * randf_range(0.45, 0.82)
			else:
				flashlight.light_energy = base_light_energy
	else:
		is_in_warning_zone = false
		if view_model and view_model.has_method("set_warning_zone"):
			view_model.set_warning_zone(false, 0.0)
		if is_flashlight_on and flashlight and not is_triggered and not is_flicker_dark:
			flashlight.light_energy = base_light_energy

		if was_in_stealth_danger:
			was_in_stealth_danger = false
			safe_hud_timer = 1.8

		if safe_hud_timer > 0.0:
			safe_hud_timer -= delta

		if view_model and view_model.has_method("update_stealth_hud"):
			if is_holding_breath:
				view_model.update_stealth_hud(4, current_stamina / max_stamina)
			elif safe_hud_timer > 0.0:
				view_model.update_stealth_hud(3)
			else:
				view_model.update_stealth_hud(0)

	# lethal hearing radius when unblocked
	if dist < 4.0 and (not is_wall_blocked or dist < 1.8):
		var is_stealth_safe: bool = is_holding_breath and not is_exhausted and horizontal_speed <= 0.2 and not is_flashlight_on
		if not is_stealth_safe:
			lethal_zone_timer += delta
			if lethal_zone_timer >= 1.2:
				lethal_zone_timer = 0.0
				if closest_monster.has_method("trigger_lethal_hearing_chase"):
					closest_monster.trigger_lethal_hearing_chase()
		else:
			lethal_zone_timer = 0.0
	else:
		lethal_zone_timer = 0.0

func trigger_jumpscare(monster_node: Node3D) -> void:
	is_jumpscared = true
	jumpscare_monster = monster_node
	velocity = Vector3.ZERO
	is_sprinting = false

	if heartbeat_player and heartbeat_player.playing:
		heartbeat_player.stop()
	beat_timer = 0.0

	if trigger_scream_player:
		if trigger_scream_player.stream == null and trigger_scream_sound != null:
			trigger_scream_player.stream = trigger_scream_sound
		if trigger_scream_player.stream and not trigger_scream_player.playing:
			trigger_scream_player.play()

	if flashlight:
		flashlight.visible = true
		flashlight.light_energy = maxf(flashlight.light_energy, 1.5)

func handle_heartbeat_audio(delta: float) -> void:
	if is_jumpscared:
		if heartbeat_player and heartbeat_player.playing:
			heartbeat_player.stop()
		beat_timer = 0.0
		return

	var closest_monster: Node3D = _get_closest_monster()
	if closest_monster == null or not is_inside_tree():
		if heartbeat_player and heartbeat_player.playing:
			heartbeat_player.stop()
		beat_timer = 0.0
		return

	var dist: float = global_position.distance_to(closest_monster.global_position)

	if dist > max_heartbeat_distance:
		if heartbeat_player and heartbeat_player.playing:
			heartbeat_player.stop()
		beat_timer = 0.0
		return

	var dist_range: float = max_heartbeat_distance - min_heartbeat_distance
	var t: float = 0.0
	if dist_range > 0.001:
		t = clampf((max_heartbeat_distance - dist) / dist_range, 0.0, 1.0)
	else:
		t = 1.0 if dist <= min_heartbeat_distance else 0.0

	current_beat_interval = lerpf(slowest_beat_interval, fastest_beat_interval, t)
	var target_vol: float = lerpf(min_heartbeat_volume_db, max_heartbeat_volume_db, t)
	var target_pitch: float = lerpf(min_heartbeat_pitch, max_heartbeat_pitch, t)

	var is_wall_blocked: bool = is_wall_blocking_to_monster(closest_monster)
	if is_wall_blocked and dist > 2.0:
		target_vol = clampf(target_vol - 8.0, min_heartbeat_volume_db, max_heartbeat_volume_db)
		current_beat_interval = minf(current_beat_interval + 0.3, slowest_beat_interval)

	if heartbeat_player:
		heartbeat_player.volume_db = target_vol
		heartbeat_player.pitch_scale = target_pitch

	# heartbeat.wav is 1.0s with silence at the tail; restart it before the stream ends
	beat_timer += delta
	if beat_timer >= current_beat_interval:
		beat_timer = 0.0
		if heartbeat_player:
			if heartbeat_player.stream == null and heartbeat_sound != null:
				heartbeat_player.stream = heartbeat_sound
			if heartbeat_player.stream != null:
				heartbeat_player.play(0.0)
		if view_model and view_model.has_method("trigger_heartbeat_pulse"):
			view_model.trigger_heartbeat_pulse()

func _get_closest_monster() -> Node3D:
	if not is_inside_tree() or get_tree() == null:
		return null
	var monsters := get_tree().get_nodes_in_group("monster")
	if monsters.is_empty():
		return null
	var closest: Node3D = null
	var min_dist: float = INF
	var my_pos: Vector3 = global_position
	for m in monsters:
		if m is Node3D and is_instance_valid(m) and m.is_inside_tree():
			var d: float = my_pos.distance_to(m.global_position)
			if d < min_dist:
				min_dist = d
				closest = m
	return closest
