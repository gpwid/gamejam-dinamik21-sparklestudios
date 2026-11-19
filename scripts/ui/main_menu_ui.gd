extends CanvasLayer

signal new_game_requested
signal brightness_changed(val: float)

@onready var new_game_btn: Button = $MarginContainer/VBoxContainer/ButtonsVBox/NewGameBtn
@onready var settings_btn: Button = $MarginContainer/VBoxContainer/ButtonsVBox/SettingsBtn
@onready var credit_btn: Button = $MarginContainer/VBoxContainer/ButtonsVBox/CreditBtn
@onready var exit_btn: Button = $MarginContainer/VBoxContainer/ButtonsVBox/ExitBtn

@onready var settings_modal: Control = $SettingsModal
@onready var settings_close_btn: Button = $SettingsModal/Panel/MarginContainer/VBoxContainer/Header/CloseBtn
@onready var volume_slider: HSlider = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/VolumeRow/VolumeSlider
@onready var volume_val_lbl: Label = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/VolumeRow/VolumeVal
@onready var brightness_slider: HSlider = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/BrightnessRow/BrightnessSlider
@onready var brightness_val_lbl: Label = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/BrightnessRow/BrightnessVal
@onready var sensitivity_slider: HSlider = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/SensitivityRow/SensitivitySlider
@onready var sensitivity_val_lbl: Label = $SettingsModal/Panel/MarginContainer/VBoxContainer/SlidersVBox/SensitivityRow/SensitivityVal

@onready var credits_modal: Control = $CreditsModal
@onready var credits_close_btn: Button = $CreditsModal/Panel/MarginContainer/VBoxContainer/Header/CreditsCloseBtn
@onready var credits_scroll: ScrollContainer = get_node_or_null("CreditsModal/Panel/MarginContainer/VBoxContainer/ScrollContainer")
var credits_auto_scroll: bool = true
var credits_scroll_pos: float = 0.0
var credits_pause_timer: float = 0.0

@onready var exit_confirm_modal: Control = $ExitConfirmModal
@onready var exit_close_btn: Button = $ExitConfirmModal/Panel/MarginContainer/VBoxContainer/Header/ExitCloseBtn
@onready var exit_yes_btn: Button = $ExitConfirmModal/Panel/MarginContainer/VBoxContainer/BtnRow/ExitYesBtn
@onready var exit_no_btn: Button = $ExitConfirmModal/Panel/MarginContainer/VBoxContainer/BtnRow/ExitNoBtn

@onready var difficulty_modal: Control = $DifficultyModal
@onready var diff_close_btn: Button = $DifficultyModal/Panel/MarginContainer/VBoxContainer/Header/DiffCloseBtn
@onready var easy_btn: Button = $DifficultyModal/Panel/MarginContainer/VBoxContainer/DiffButtonsVBox/EasyBtn
@onready var normal_btn: Button = $DifficultyModal/Panel/MarginContainer/VBoxContainer/DiffButtonsVBox/NormalBtn
@onready var hard_btn: Button = $DifficultyModal/Panel/MarginContainer/VBoxContainer/DiffButtonsVBox/HardBtn
@onready var extreme_btn: Button = $DifficultyModal/Panel/MarginContainer/VBoxContainer/DiffButtonsVBox/ExtremeBtn

@onready var fade_rect: ColorRect = $FadeRect
@onready var ui_sfx: AudioStreamPlayer = $UiSfx

var is_transitioning: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if GameManager:
		GameManager.play_menu_music()

	_setup_button(new_game_btn, _on_new_game_pressed)
	_setup_button(settings_btn, _on_settings_pressed)
	_setup_button(credit_btn, _on_credit_pressed)
	_setup_button(exit_btn, _on_exit_pressed)

	if settings_close_btn:
		_setup_button(settings_close_btn, _on_settings_close_pressed)
	if volume_slider:
		volume_slider.value_changed.connect(_on_volume_changed)
	if brightness_slider:
		brightness_slider.value_changed.connect(_on_brightness_changed)
	if sensitivity_slider:
		sensitivity_slider.value_changed.connect(_on_sensitivity_changed)

	if credits_close_btn:
		_setup_button(credits_close_btn, _on_credits_close_pressed)
	if credits_scroll:
		credits_scroll.gui_input.connect(_on_credits_scroll_input)

	if exit_close_btn:
		_setup_button(exit_close_btn, _on_exit_cancel_pressed)
	if exit_no_btn:
		_setup_button(exit_no_btn, _on_exit_cancel_pressed)
	if exit_yes_btn:
		_setup_button(exit_yes_btn, _on_exit_confirm_pressed)

	if diff_close_btn:
		_setup_button(diff_close_btn, _on_diff_close_pressed)
	if easy_btn:
		_setup_button(easy_btn, func(): _select_difficulty(GameManager.Difficulty.EASY))
	if normal_btn:
		_setup_button(normal_btn, func(): _select_difficulty(GameManager.Difficulty.NORMAL))
	if hard_btn:
		_setup_button(hard_btn, func(): _select_difficulty(GameManager.Difficulty.HARD))
	if extreme_btn:
		_setup_button(extreme_btn, func(): _select_difficulty(GameManager.Difficulty.EXTREME))

	_update_difficulty_buttons()
	_close_all_modals()

	if fade_rect:
		fade_rect.visible = true
		fade_rect.color = Color(0, 0, 0, 1)
		fade_rect.modulate = Color(1, 1, 1, 1)
		var tween := create_tween()
		tween.tween_property(fade_rect, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			fade_rect.visible = false
		)

func _setup_button(btn: Button, callback: Callable) -> void:
	if btn == null:
		return
	btn.pressed.connect(func():
		_play_sfx()
		callback.call()
	)
	btn.mouse_entered.connect(func():
		_play_sfx(0.85)
	)

func _play_sfx(pitch: float = 1.0) -> void:
	if ui_sfx and ui_sfx.stream:
		ui_sfx.pitch_scale = pitch
		ui_sfx.play()

func _close_all_modals() -> void:
	if settings_modal:
		settings_modal.visible = false
	if credits_modal:
		credits_modal.visible = false
	if exit_confirm_modal:
		exit_confirm_modal.visible = false
	if difficulty_modal:
		difficulty_modal.visible = false

func _on_new_game_pressed() -> void:
	_close_all_modals()
	_update_difficulty_buttons()
	if difficulty_modal:
		difficulty_modal.visible = true

func _update_difficulty_buttons() -> void:
	if not GameManager:
		return
	if easy_btn:
		easy_btn.text = "> EASY          [BEST: %s]" % GameManager.get_best_time_string(GameManager.Difficulty.EASY)
	if normal_btn:
		normal_btn.text = "> NORMAL     [BEST: %s]" % GameManager.get_best_time_string(GameManager.Difficulty.NORMAL)
	if hard_btn:
		hard_btn.text = "> HARD          [BEST: %s]" % GameManager.get_best_time_string(GameManager.Difficulty.HARD)
	if extreme_btn:
		extreme_btn.text = "> EXTREME  [BEST: %s]" % GameManager.get_best_time_string(GameManager.Difficulty.EXTREME)

func _select_difficulty(diff: GameManager.Difficulty) -> void:
	if GameManager:
		GameManager.current_difficulty = diff
	new_game_requested.emit()
	start_game_transition("res://scenes/level/main_map.tscn")

func start_game_transition(target_scene: String = "res://scenes/level/main_map.tscn") -> void:
	if is_transitioning:
		return
	is_transitioning = true
	if fade_rect:
		fade_rect.visible = true
		fade_rect.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(fade_rect, "modulate:a", 1.0, 0.45)
		tween.tween_callback(func():
			get_tree().change_scene_to_file(target_scene)
		)
	else:
		get_tree().change_scene_to_file(target_scene)

func _on_settings_pressed() -> void:
	_close_all_modals()
	if settings_modal:
		settings_modal.visible = true

func _on_settings_close_pressed() -> void:
	if settings_modal:
		settings_modal.visible = false

func _process(delta: float) -> void:
	if credits_modal and credits_modal.visible and credits_scroll:
		if credits_pause_timer > 0.0:
			credits_pause_timer -= delta
		elif credits_auto_scroll:
			credits_scroll_pos += delta * 22.0
			credits_scroll.scroll_vertical = int(credits_scroll_pos)

func _on_credit_pressed() -> void:
	_close_all_modals()
	if credits_modal:
		credits_modal.visible = true
	if credits_scroll:
		credits_scroll_pos = 0.0
		credits_scroll.scroll_vertical = 0
		credits_auto_scroll = true
		credits_pause_timer = 0.5

func _on_credits_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			credits_pause_timer = 4.0
			if credits_scroll:
				credits_scroll_pos = float(credits_scroll.scroll_vertical)

func _on_credits_close_pressed() -> void:
	if credits_modal:
		credits_modal.visible = false

func _on_exit_pressed() -> void:
	_close_all_modals()
	if exit_confirm_modal:
		exit_confirm_modal.visible = true

func _on_exit_cancel_pressed() -> void:
	if exit_confirm_modal:
		exit_confirm_modal.visible = false

func _on_exit_confirm_pressed() -> void:
	get_tree().quit()

func _on_diff_close_pressed() -> void:
	if difficulty_modal:
		difficulty_modal.visible = false

func _on_volume_changed(val: float) -> void:
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
	if GameManager:
		GameManager.set_music_volume_percent(val)

func _on_brightness_changed(val: float) -> void:
	if brightness_val_lbl:
		brightness_val_lbl.text = "%d%%" % int(val)
	brightness_changed.emit(val)

func _on_sensitivity_changed(val: float) -> void:
	if sensitivity_val_lbl:
		sensitivity_val_lbl.text = "%d%%" % int(val)
