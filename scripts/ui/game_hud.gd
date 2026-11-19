extends CanvasLayer
class_name GameHUD

@onready var counter_label: Label = $TopMargin/CounterLabel
@onready var hint_container: MarginContainer = $BottomMargin/HintContainer
@onready var hint_box: HBoxContainer = $BottomMargin/HintContainer/HBox

@export var ellipse_texture: Texture2D = preload("res://assets/ui/ui_control_ellipse.png")
@export var pill_texture: Texture2D = preload("res://assets/ui/ui_control_pill.png")
@export var font_resource: FontFile = preload("res://assets/fonts/HandymandiFree.ttf")

var hint_tween: Tween
var counter_pulse_tween: Tween
var active_hint_type: String = ""

func _ready() -> void:
	if hint_container:
		hint_container.modulate.a = 0.0
		hint_container.visible = false

func set_counter(current: int, total: int) -> void:
	if counter_label:
		if current >= total and total > 0:
			counter_label.text = "CARI JALAN KELUAR"
			_start_counter_pulse()
		else:
			counter_label.text = "%d/%d" % [current, total]
			_stop_counter_pulse()

func _start_counter_pulse() -> void:
	if counter_pulse_tween and counter_pulse_tween.is_valid():
		return
	counter_pulse_tween = create_tween().set_loops()
	counter_pulse_tween.tween_property(counter_label, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.65).set_trans(Tween.TRANS_SINE)
	counter_pulse_tween.tween_property(counter_label, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.65).set_trans(Tween.TRANS_SINE)

func _stop_counter_pulse() -> void:
	if counter_pulse_tween and counter_pulse_tween.is_valid():
		counter_pulse_tween.kill()
		counter_pulse_tween = null
	if counter_label:
		counter_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

func show_hint(type: String) -> void:
	if hint_container == null or hint_box == null:
		return

	active_hint_type = type

	for child in hint_box.get_children():
		child.queue_free()

	match type:
		"spawn":
			_add_hint_item("Q", "Echolocation", false)
			_add_hint_item("SHIFT", "Lari (Sprint)", true)
			_fade_in_hint(6.5)
		"flashlight":
			_add_hint_item("F", "Senter (Flashlight)", false)
			_fade_in_hint(5.0)
		"switch":
			_add_hint_item("E", "Nyalakan Saklar", false)
			_fade_in_hint(4.0)
		"breath":
			_add_hint_item("SHIFT", "Tahan Napas", true)
			_fade_in_hint(5.0)

func hide_hint() -> void:
	if hint_container == null:
		return
	if hint_tween and hint_tween.is_valid():
		hint_tween.kill()
	hint_tween = create_tween()
	hint_tween.tween_property(hint_container, "modulate:a", 0.0, 0.35)
	hint_tween.tween_callback(func():
		if hint_container:
			hint_container.visible = false
		active_hint_type = ""
	)

func _fade_in_hint(duration: float) -> void:
	if hint_tween and hint_tween.is_valid():
		hint_tween.kill()

	hint_container.visible = true
	hint_tween = create_tween()
	hint_tween.tween_property(hint_container, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hint_tween.tween_interval(duration)
	hint_tween.tween_property(hint_container, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hint_tween.tween_callback(func():
		if hint_container:
			hint_container.visible = false
		active_hint_type = ""
	)

func _add_hint_item(badge_text: String, label_text: String, is_pill: bool) -> void:
	var item_hbox := HBoxContainer.new()
	item_hbox.add_theme_constant_override("separation", 8)

	var badge := TextureRect.new()
	badge.texture = pill_texture if is_pill else ellipse_texture
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.custom_minimum_size = Vector2(62, 30) if is_pill else Vector2(34, 34)

	var badge_lbl := Label.new()
	badge_lbl.text = badge_text
	badge_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_lbl.add_theme_font_override("font", font_resource)
	badge_lbl.add_theme_font_size_override("font_size", 13 if is_pill else 15)
	badge_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	badge_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	badge_lbl.add_theme_constant_override("outline_size", 2)
	badge.add_child(badge_lbl)

	item_hbox.add_child(badge)

	var desc_lbl := Label.new()
	desc_lbl.text = label_text
	desc_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	desc_lbl.add_theme_font_override("font", font_resource)
	desc_lbl.add_theme_font_size_override("font_size", 15)
	desc_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1))
	desc_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	desc_lbl.add_theme_constant_override("outline_size", 2)
	item_hbox.add_child(desc_lbl)

	hint_box.add_child(item_hbox)
