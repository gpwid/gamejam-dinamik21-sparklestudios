extends Node

func _ready() -> void:
	print("--- TEST BEST TIME SYSTEM ---")

	# Test 1: format_time
	assert(GameManager.format_time(0.0) == "--:--", "0.0 should format as --:--")
	assert(GameManager.format_time(65.0) == "01:05", "65.0 should format as 01:05")
	assert(GameManager.format_time(125.4) == "02:05", "125.4 should format as 02:05")
	print("PASS: format_time behaves correctly")

	# Test 2: save_best_time and records persistence
	var test_path: String = "user://records.cfg"
	var prev_easy: float = GameManager.get_best_time(GameManager.Difficulty.EASY)

	# Set a initial test record
	var first_record: float = 120.0
	var is_new: bool = GameManager.save_best_time(GameManager.Difficulty.EASY, first_record)
	assert(GameManager.get_best_time(GameManager.Difficulty.EASY) == first_record, "Easy record should be set")

	# Slower time should NOT beat record
	var slower_time: float = 150.0
	var is_slower_new: bool = GameManager.save_best_time(GameManager.Difficulty.EASY, slower_time)
	assert(is_slower_new == false, "Slower time must not beat record")
	assert(GameManager.get_best_time(GameManager.Difficulty.EASY) == first_record, "Record should remain first_record")

	# Faster time SHOULD beat record
	var faster_time: float = 95.0
	var is_faster_new: bool = GameManager.save_best_time(GameManager.Difficulty.EASY, faster_time)
	assert(is_faster_new == true, "Faster time must beat record")
	assert(GameManager.get_best_time(GameManager.Difficulty.EASY) == faster_time, "Record should update to faster_time")

	# Reload from disk
	GameManager.load_records()
	assert(GameManager.get_best_time(GameManager.Difficulty.EASY) == faster_time, "Reloaded record from disk must match")
	print("PASS: save_best_time and persistence verified")

	# Test 3: VictoryUI instantiation and show_victory
	var victory_scene: PackedScene = load("res://scenes/ui/victory_ui.tscn")
	assert(victory_scene != null, "victory_ui.tscn must load")
	var victory_ui = victory_scene.instantiate()
	add_child(victory_ui)
	victory_ui.show_victory(80.0, 3, 3)
	assert(victory_ui.visible == true, "victory_ui should be visible")
	assert(victory_ui.best_time_label != null, "best_time_label should be connected")
	print("PASS: VictoryUI displays best time")

	# Test 4: MainMenuUI instantiation and difficulty buttons
	var menu_scene: PackedScene = load("res://scenes/ui/main_menu_ui.tscn")
	assert(menu_scene != null, "main_menu_ui.tscn must load")
	var menu_ui = menu_scene.instantiate()
	add_child(menu_ui)
	menu_ui._on_new_game_pressed()
	assert(menu_ui.easy_btn.text.contains("[BEST:"), "Easy button must contain [BEST:")
	print("Easy btn text: %s" % menu_ui.easy_btn.text)
	print("PASS: MainMenuUI displays best time")

	# Restore previous record
	GameManager.best_times[GameManager.Difficulty.EASY] = prev_easy
	var cfg := ConfigFile.new()
	cfg.load(test_path)
	cfg.set_value("best_time", "easy", prev_easy)
	cfg.save(test_path)

	print("--- ALL BEST TIME TESTS PASSED ---")
	get_tree().quit(0)
