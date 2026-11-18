extends CanvasLayer
class_name PauseMenu

@onready var menu_root: Control = $MenuRoot
@onready var dimmer_overlay: ColorRect = $MenuRoot/DimmerOverlay
@onready var left_gradient: TextureRect = $MenuRoot/LeftGradient
@onready var menu_content: MarginContainer = $MenuRoot/MenuContent
@onready var buttons_vbox: VBoxContainer = $MenuRoot/MenuContent/VBoxContainer/ButtonsVBox

@onready var resume_btn: Button = $MenuRoot/MenuContent/VBoxContainer/ButtonsVBox/ResumeBtn
@onready var settings_btn: Button = $MenuRoot/MenuContent/VBoxContainer/ButtonsVBox/SettingsBtn
@onready var restart_btn: Button = $MenuRoot/MenuContent/VBoxContainer/ButtonsVBox/RestartBtn
@onready var main_menu_btn: Button = $MenuRoot/MenuContent/VBoxContainer/ButtonsVBox/MainMenuBtn
@onready var quit_btn: Button = $MenuRoot/MenuContent/VBoxContainer/ButtonsVBox/QuitBtn

# Settings Modal
@onready var settings_modal: Control = $SettingsModal
@onready var settings_close_btn: Button = $SettingsModal/Panel/MarginContainer/VBoxContainer/Header/CloseBtn
@onready var volume_slider: HSlider = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/VolumeRow/VolumeSlider
@onready var volume_val_lbl: Label = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/VolumeRow/VolumeVal
@onready var brightness_slider: HSlider = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/BrightnessRow/BrightnessSlider
@onready var brightness_val_lbl: Label = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/BrightnessRow/BrightnessVal
@onready var sensitivity_slider: HSlider = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/SensitivityRow/SensitivitySlider
@onready var sensitivity_val_lbl: Label = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/SensitivityRow/SensitivityVal

# Confirmation Modal
@onready var confirm_modal: Control = $ConfirmModal
@onready var confirm_title_lbl: Label = $ConfirmModal/Panel/MarginContainer/VBoxContainer/Header/Title
@onready var confirm_close_btn: Button = $ConfirmModal/Panel/MarginContainer/VBoxContainer/Header/CloseBtn
@onready var confirm_question_lbl: Label = $ConfirmModal/Panel/MarginContainer/VBoxContainer/Question
@onready var confirm_yes_btn: Button = $ConfirmModal/Panel/MarginContainer/VBoxContainer/BtnRow/ConfirmYesBtn
@onready var confirm_no_btn: Button = $ConfirmModal/Panel/MarginContainer/VBoxContainer/BtnRow/ConfirmNoBtn

@onready var fade_rect: ColorRect = $FadeRect
@onready var ui_sfx: AudioStreamPlayer = $UiSfx

var is_paused: bool = false
var is_transitioning: bool = false
var previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var pending_confirm_action: Callable = Callable()

# Static settings agar tersimpan & tersinkronisasi lintas scene / restart
static var saved_volume: float = 80.0
static var saved_brightness: float = 50.0
static var saved_sensitivity: float = 50.0
static var settings_initialized: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if fade_rect:
		fade_rect.visible = false

	_init_settings()

	# Hubungkan tombol menu utama
	_setup_menu_button(resume_btn, "RESUME", resume_game)
	_setup_menu_button(settings_btn, "SETTINGS", _on_settings_pressed)
	_setup_menu_button(restart_btn, "RESTART", _on_restart_pressed)
	_setup_menu_button(main_menu_btn, "MAIN MENU", _on_main_menu_pressed)
	_setup_menu_button(quit_btn, "QUIT GAME", _on_quit_pressed)

	# Hubungkan tombol modal settings
	if settings_close_btn:
		_setup_button(settings_close_btn, _close_settings_modal)
	if volume_slider:
		volume_slider.value_changed.connect(_on_volume_changed)
	if brightness_slider:
		brightness_slider.value_changed.connect(_on_brightness_changed)
	if sensitivity_slider:
		sensitivity_slider.value_changed.connect(_on_sensitivity_changed)

	# Hubungkan tombol modal konfirmasi
	if confirm_close_btn:
		_setup_button(confirm_close_btn, _close_confirm_modal)
	if confirm_no_btn:
		_setup_menu_button(confirm_no_btn, "BATAL", _close_confirm_modal)
	if confirm_yes_btn:
		_setup_menu_button(confirm_yes_btn, "YA", _on_confirm_yes_pressed)

	_close_all_modals()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE):
		if is_transitioning:
			get_viewport().set_input_as_handled()
			return

		# Jika modal konfirmasi terbuka, tutup modal saja (jangan resume / pause toggle)
		if confirm_modal and confirm_modal.visible:
			_close_confirm_modal()
			get_viewport().set_input_as_handled()
			return

		# Jika modal settings terbuka, tutup settings saja (jangan resume / pause toggle)
		if settings_modal and settings_modal.visible:
			_close_settings_modal()
			get_viewport().set_input_as_handled()
			return

		# Toggle pause jika tidak ada modal yang terbuka
		if is_paused:
			resume_game()
			get_viewport().set_input_as_handled()
		else:
			if _can_pause():
				pause_game()
				get_viewport().set_input_as_handled()

func _can_pause() -> bool:
	if is_transitioning:
		return false

	# Jangan izinkan pause saat tertangkap jumpscare
	var p := _find_player()
	if p and "is_jumpscared" in p and p.is_jumpscared:
		return false

	# Jangan izinkan pause saat game selesai / layar kemenangan
	var parent_node := get_parent()
	if parent_node and "is_game_finished" in parent_node and parent_node.is_game_finished:
		return false

	var curr_scene = get_tree().current_scene
	if curr_scene:
		if "is_game_finished" in curr_scene and curr_scene.is_game_finished:
			return false
		var victory_node = curr_scene.find_child("VictoryUI", true, false)
		if victory_node and "is_active" in victory_node and victory_node.is_active:
			return false

	if parent_node:
		var victory_node = parent_node.find_child("VictoryUI", true, false)
		if victory_node and "is_active" in victory_node and victory_node.is_active:
			return false

	return true

# ==============================================================================
# PAUSE & RESUME
# ==============================================================================
func pause_game() -> void:
	if is_paused or not _can_pause():
		return

	is_paused = true
	previous_mouse_mode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true

	_close_all_modals()
	visible = true
	if menu_root:
		menu_root.visible = true
		menu_root.modulate.a = 0.0

	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	if menu_root:
		tween.tween_property(menu_root, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if menu_content:
		var target_left := 72.0
		menu_content.offset_left = 40.0
		tween.tween_property(menu_content, "offset_left", target_left, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_play_sfx(1.0)

	if resume_btn and resume_btn.focus_mode != Control.FOCUS_NONE:
		resume_btn.grab_focus()

func resume_game() -> void:
	if not is_paused or is_transitioning:
		return

	is_paused = false
	_close_all_modals()

	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if menu_root:
		tween.tween_property(menu_root, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		visible = false
		get_tree().paused = false
		Input.set_mouse_mode(previous_mouse_mode)
	)

	_play_sfx(0.9)

# ==============================================================================
# BUTTON ACTIONS & CONFIRMATION
# ==============================================================================
func _on_settings_pressed() -> void:
	_close_all_modals()
	if settings_modal:
		settings_modal.visible = true
		settings_modal.modulate.a = 0.0
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(settings_modal, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _close_settings_modal() -> void:
	if settings_modal:
		settings_modal.visible = false
	if settings_btn and settings_btn.focus_mode != Control.FOCUS_NONE:
		settings_btn.grab_focus()

func _on_restart_pressed() -> void:
	_open_confirm_modal(
		"ULANGI PERMAINAN",
		"Ulangi permainan dari awal?\nSemua saklar dan progres sesi ini akan di-reset.",
		_execute_restart
	)

func _execute_restart() -> void:
	if is_transitioning:
		return
	is_transitioning = true

	# Pastikan status pause dibersihkan dengan benar sebelum reload
	get_tree().paused = false
	Input.set_mouse_mode(previous_mouse_mode)

	if fade_rect:
		fade_rect.visible = true
		fade_rect.modulate.a = 0.0
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(fade_rect, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			get_tree().reload_current_scene()
		)
	else:
		get_tree().reload_current_scene()

func _on_main_menu_pressed() -> void:
	_open_confirm_modal(
		"MENU UTAMA",
		"Kembali ke Menu Utama?\nProgres permainan yang belum selesai tidak akan tersimpan.",
		_execute_main_menu
	)

func _execute_main_menu() -> void:
	if is_transitioning:
		return
	is_transitioning = true

	# Pastikan status pause dibersihkan sebelum berpindah scene
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var gm := _get_game_manager()
	if gm and gm.has_method("stop_music"):
		gm.stop_music(0.4)

	if fade_rect:
		fade_rect.visible = true
		fade_rect.modulate.a = 0.0
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(fade_rect, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		)
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_quit_pressed() -> void:
	_open_confirm_modal(
		"KELUAR PERMAINAN",
		"Apakah anda yakin ingin keluar dari permainan?",
		_execute_quit
	)

func _execute_quit() -> void:
	get_tree().quit()

func _open_confirm_modal(title: String, question: String, on_confirm: Callable) -> void:
	_close_all_modals()
	if confirm_title_lbl:
		confirm_title_lbl.text = title
	if confirm_question_lbl:
		confirm_question_lbl.text = question
	pending_confirm_action = on_confirm

	if confirm_modal:
		confirm_modal.visible = true
		confirm_modal.modulate.a = 0.0
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(confirm_modal, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if confirm_no_btn and confirm_no_btn.focus_mode != Control.FOCUS_NONE:
		confirm_no_btn.grab_focus()

func _close_confirm_modal() -> void:
	if confirm_modal:
		confirm_modal.visible = false
	pending_confirm_action = Callable()

func _on_confirm_yes_pressed() -> void:
	if pending_confirm_action.is_valid():
		var action := pending_confirm_action
		_close_confirm_modal()
		action.call()

func _close_all_modals() -> void:
	if settings_modal:
		settings_modal.visible = false
	if confirm_modal:
		confirm_modal.visible = false

# ==============================================================================
# SETTINGS LOGIC
# ==============================================================================
func _init_settings() -> void:
	if not settings_initialized:
		var bus_idx := AudioServer.get_bus_index("Master")
		if bus_idx >= 0:
			if AudioServer.is_bus_mute(bus_idx):
				saved_volume = 0.0
			else:
				var vol_db := AudioServer.get_bus_volume_db(bus_idx)
				saved_volume = clampf(db_to_linear(vol_db) * 100.0, 0.0, 100.0)
		settings_initialized = true

	if volume_slider:
		volume_slider.value = saved_volume
	if volume_val_lbl:
		volume_val_lbl.text = "%d%%" % int(saved_volume)

	if brightness_slider:
		brightness_slider.value = saved_brightness
	if brightness_val_lbl:
		brightness_val_lbl.text = "%d%%" % int(saved_brightness)

	if sensitivity_slider:
		sensitivity_slider.value = saved_sensitivity
	if sensitivity_val_lbl:
		sensitivity_val_lbl.text = "%d%%" % int(saved_sensitivity)

	_on_brightness_changed(saved_brightness)
	_on_sensitivity_changed(saved_sensitivity)

func _on_volume_changed(val: float) -> void:
	saved_volume = val
	if volume_val_lbl:
		volume_val_lbl.text = "%d%%" % int(val)
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		if val <= 0:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			var vol_db := linear_to_db(val / 100.0)
			AudioServer.set_bus_volume_db(bus_idx, vol_db)
	var gm := _get_game_manager()
	if gm and gm.has_method("set_music_volume_percent"):
		gm.set_music_volume_percent(val)

func _on_brightness_changed(val: float) -> void:
	saved_brightness = val
	if brightness_val_lbl:
		brightness_val_lbl.text = "%d%%" % int(val)
	var env_node := _find_world_environment()
	if env_node and env_node.environment:
		var exp_factor := 0.4 + (val / 100.0) * 1.4
		env_node.environment.tonemap_exposure = exp_factor

func _on_sensitivity_changed(val: float) -> void:
	saved_sensitivity = val
	if sensitivity_val_lbl:
		sensitivity_val_lbl.text = "%d%%" % int(val)
	var p := _find_player()
	if p and "mouse_sensitivity" in p:
		p.mouse_sensitivity = 0.003 * (val / 50.0)

# ==============================================================================
# UI HELPERS & SFX
# ==============================================================================
func _setup_menu_button(btn: Button, base_title: String, callback: Callable) -> void:
	if btn == null:
		return
	btn.text = base_title
	btn.pressed.connect(func():
		_play_sfx(1.0)
		callback.call()
	)
	btn.mouse_entered.connect(func():
		btn.text = "> " + base_title
		_play_sfx(0.85)
	)
	btn.mouse_exited.connect(func():
		btn.text = base_title
	)
	btn.focus_entered.connect(func():
		btn.text = "> " + base_title
	)
	btn.focus_exited.connect(func():
		btn.text = base_title
	)

func _setup_button(btn: Button, callback: Callable) -> void:
	if btn == null:
		return
	btn.pressed.connect(func():
		_play_sfx(1.0)
		callback.call()
	)
	btn.mouse_entered.connect(func():
		_play_sfx(0.85)
	)

func _play_sfx(pitch: float = 1.0) -> void:
	if ui_sfx and ui_sfx.stream:
		ui_sfx.pitch_scale = pitch
		ui_sfx.play()

func _find_player() -> Node:
	if get_parent() and get_parent().has_node("Player"):
		return get_parent().get_node("Player")
	var curr = get_tree().current_scene
	if curr:
		return curr.find_child("Player", true, false)
	return null

func _find_world_environment() -> WorldEnvironment:
	if get_parent() and get_parent().has_node("WorldEnvironment"):
		return get_parent().get_node("WorldEnvironment") as WorldEnvironment
	var curr = get_tree().current_scene
	if curr:
		return curr.find_child("WorldEnvironment", true, false) as WorldEnvironment
	return null

func _get_game_manager() -> Node:
	if is_inside_tree() and get_tree().root and get_tree().root.has_node("GameManager"):
		return get_tree().root.get_node("GameManager")
	return null
