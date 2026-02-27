extends GdUnitTestSuite
## Tests for SaveManager autoload.

const TEST_SLOT := 0
var _original_gm_state: Dictionary
var _original_rm_state: Dictionary
var _original_cbm_state: Dictionary


func before_test() -> void:
	_original_gm_state = GameManager.save_state()
	_original_rm_state = ResourceManager.save_state()
	_original_cbm_state = CivBonusManager.save_state()
	# Clean test slot
	SaveManager.delete_save(TEST_SLOT)


func after_test() -> void:
	GameManager.load_state(_original_gm_state)
	ResourceManager.load_state(_original_rm_state)
	CivBonusManager.load_state(_original_cbm_state)
	# Clean up saves
	for i in SaveManager.MAX_SLOTS:
		SaveManager.delete_save(i)


func test_save_creates_file() -> void:
	var ok := SaveManager.save_game(TEST_SLOT)
	assert_bool(ok).is_true()
	var path := SaveManager.SAVE_DIR + "slot_%d.json" % TEST_SLOT
	assert_bool(FileAccess.file_exists(path)).is_true()


func test_load_returns_matching_data() -> void:
	GameManager.game_time = 123.0
	GameManager.current_age = 2
	SaveManager.save_game(TEST_SLOT)
	var data := SaveManager.load_game(TEST_SLOT)
	assert_bool(data.is_empty()).is_false()
	var gm: Dictionary = data.get("game_manager", {})
	assert_float(float(gm.get("game_time", 0.0))).is_equal_approx(123.0, 0.1)
	assert_int(int(gm.get("current_age", -1))).is_equal(2)


func test_round_trip_preserves_state() -> void:
	GameManager.game_time = 456.0
	GameManager.current_age = 3
	GameManager.ai_difficulty = "hard"
	SaveManager.save_game(TEST_SLOT)
	# Modify state after save
	GameManager.game_time = 0.0
	GameManager.current_age = 0
	GameManager.ai_difficulty = "normal"
	# Load and apply
	var data := SaveManager.load_game(TEST_SLOT)
	SaveManager.apply_loaded_state(data)
	assert_float(GameManager.game_time).is_equal_approx(456.0, 0.1)
	assert_int(GameManager.current_age).is_equal(3)
	assert_str(GameManager.ai_difficulty).is_equal("hard")


func test_empty_slot_returns_not_exists() -> void:
	var info := SaveManager.get_save_info(1)
	assert_bool(info.get("exists", true)).is_false()


func test_delete_removes_file() -> void:
	SaveManager.save_game(TEST_SLOT)
	var path := SaveManager.SAVE_DIR + "slot_%d.json" % TEST_SLOT
	assert_bool(FileAccess.file_exists(path)).is_true()
	var ok := SaveManager.delete_save(TEST_SLOT)
	assert_bool(ok).is_true()
	assert_bool(FileAccess.file_exists(path)).is_false()


func test_save_info_has_correct_metadata() -> void:
	GameManager.current_age = 4
	GameManager.set_player_civilization(0, "rome")
	SaveManager.save_game(TEST_SLOT)
	var info := SaveManager.get_save_info(TEST_SLOT)
	assert_bool(info.get("exists", false)).is_true()
	assert_str(info.get("civ_name", "")).is_equal("rome")
	assert_str(info.get("age_name", "")).is_equal("Industrial Age")
	assert_bool(float(info.get("timestamp", 0.0)) > 0.0).is_true()


func test_invalid_slot_returns_false() -> void:
	var ok := SaveManager.save_game(-1)
	assert_bool(ok).is_false()
	ok = SaveManager.save_game(SaveManager.MAX_SLOTS)
	assert_bool(ok).is_false()


func test_load_nonexistent_returns_empty() -> void:
	var data := SaveManager.load_game(2)
	assert_bool(data.is_empty()).is_true()


func test_save_includes_version() -> void:
	SaveManager.save_game(TEST_SLOT)
	var data := SaveManager.load_game(TEST_SLOT)
	assert_int(int(data.get("version", 0))).is_equal(SaveManager.SAVE_VERSION)


func test_max_slots_constant() -> void:
	assert_int(SaveManager.MAX_SLOTS).is_equal(3)


func test_save_version_is_2() -> void:
	assert_int(SaveManager.SAVE_VERSION).is_equal(2)


func test_v1_migration_adds_scene_key() -> void:
	var v1_data := {
		"version": 1,
		"timestamp": 1000.0,
		"game_manager": GameManager.save_state(),
		"resource_manager": ResourceManager.save_state(),
		"civ_bonus_manager": CivBonusManager.save_state(),
	}
	# Write a v1 save manually
	var path := SaveManager.SAVE_DIR + "slot_%d.json" % TEST_SLOT
	var dir := DirAccess.open("user://")
	if dir != null and not DirAccess.dir_exists_absolute(SaveManager.SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(v1_data))
	file.close()
	var loaded := SaveManager.load_game(TEST_SLOT)
	assert_int(int(loaded.get("version", 0))).is_equal(2)
	assert_bool(loaded.has("scene")).is_true()
	assert_bool(loaded["scene"] is Dictionary).is_true()


func test_scene_provider_save_includes_scene_key() -> void:
	var mock_provider := Node.new()
	mock_provider.set_script(load("res://tests/autoloads/mock_scene_provider.gd"))
	add_child(mock_provider)
	SaveManager.register_scene_provider(mock_provider)
	SaveManager.save_game(TEST_SLOT)
	var data := SaveManager.load_game(TEST_SLOT)
	assert_bool(data.has("scene")).is_true()
	var scene: Dictionary = data.get("scene", {})
	assert_bool(scene.has("test_key")).is_true()
	assert_str(str(scene.get("test_key", ""))).is_equal("test_value")
	SaveManager.register_scene_provider(null)
	mock_provider.queue_free()


func test_apply_without_scene_provider_skips_scene() -> void:
	SaveManager.register_scene_provider(null)
	var data := {
		"version": 2,
		"game_manager": GameManager.save_state(),
		"resource_manager": ResourceManager.save_state(),
		"civ_bonus_manager": CivBonusManager.save_state(),
		"scene": {"units": []},
	}
	# Should not crash when no provider is registered
	SaveManager.apply_loaded_state(data)
