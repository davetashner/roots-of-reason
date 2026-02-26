extends GdUnitTestSuite
## Tests for victory_manager.gd — defeat, military/singularity/wonder victory conditions.

const VictoryManagerScript := preload("res://scripts/prototype/victory_manager.gd")

var _defeated_ids: Array = []
var _victory_ids: Array = []
var _victory_conditions: Array = []
var _wonder_started_ids: Array = []
var _wonder_cancelled_ids: Array = []


func _reset_signals() -> void:
	_defeated_ids.clear()
	_victory_ids.clear()
	_victory_conditions.clear()
	_wonder_started_ids.clear()
	_wonder_cancelled_ids.clear()


func _on_player_defeated(pid: int) -> void:
	_defeated_ids.append(pid)


func _on_player_victorious(pid: int, condition: String) -> void:
	_victory_ids.append(pid)
	_victory_conditions.append(condition)


func _on_wonder_started(pid: int, _duration: float) -> void:
	_wonder_started_ids.append(pid)


func _on_wonder_cancelled(pid: int) -> void:
	_wonder_cancelled_ids.append(pid)


class MockBuildingPlacer:
	extends Node
	signal building_placed(building: Node2D)
	var _placed_buildings: Array[Dictionary] = []


class MockBuilding:
	extends Node2D
	signal construction_complete(building: Node2D)
	signal building_destroyed(building: Node2D)
	var building_name: String = ""
	var grid_pos: Vector2i = Vector2i.ZERO
	var owner_id: int = 0
	var under_construction: bool = false
	var hp: int = 100
	var max_hp: int = 100
	var last_attacker_id: int = -1


func _create_manager(placer: Node = null) -> Node:
	var mgr := Node.new()
	mgr.name = "VictoryManager"
	mgr.set_script(VictoryManagerScript)
	add_child(mgr)
	auto_free(mgr)
	# Override config for deterministic tests
	mgr._wonder_countdown_duration = 10.0
	mgr._defeat_delay = 0.0
	mgr._singularity_age = 6
	mgr._allow_continue = true
	if placer != null:
		mgr.setup(placer)
	_reset_signals()
	mgr.player_defeated.connect(_on_player_defeated)
	mgr.player_victorious.connect(_on_player_victorious)
	mgr.wonder_countdown_started.connect(_on_wonder_started)
	mgr.wonder_countdown_cancelled.connect(_on_wonder_cancelled)
	return mgr


func _create_tc(pid: int, gpos: Vector2i = Vector2i.ZERO) -> Node2D:
	var b := MockBuilding.new()
	b.building_name = "town_center"
	b.owner_id = pid
	b.grid_pos = gpos
	add_child(b)
	auto_free(b)
	return b


func _create_wonder(pid: int, gpos: Vector2i = Vector2i.ZERO) -> Node2D:
	var b := MockBuilding.new()
	b.building_name = "wonder"
	b.owner_id = pid
	b.grid_pos = gpos
	add_child(b)
	auto_free(b)
	return b


func test_player_not_defeated_with_tc() -> void:
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	assert_bool(mgr.check_defeat(0)).is_false()


func test_player_defeated_with_no_tcs() -> void:
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	mgr.unregister_town_center(0, tc)
	assert_bool(mgr.check_defeat(0)).is_true()


func test_player_not_defeated_with_remaining_tc() -> void:
	var mgr := _create_manager()
	var tc1 := _create_tc(0, Vector2i(0, 0))
	var tc2 := _create_tc(0, Vector2i(10, 10))
	mgr.register_town_center(0, tc1)
	mgr.register_town_center(0, tc2)
	mgr.unregister_town_center(0, tc1)
	assert_bool(mgr.check_defeat(0)).is_false()


func test_defeat_signal_emitted_on_tc_destruction() -> void:
	var mgr := _create_manager()
	var tc := _create_tc(1)
	mgr.register_town_center(1, tc)
	# Simulate destruction via the building_destroyed signal
	mgr._on_building_destroyed(tc)
	assert_array(_defeated_ids).contains([1])


func test_military_victory_when_all_enemies_defeated() -> void:
	var mgr := _create_manager()
	# Player 0 has a TC
	var tc0 := _create_tc(0)
	mgr.register_town_center(0, tc0)
	# Player 1 has a TC, then loses it
	var tc1 := _create_tc(1)
	mgr.register_town_center(1, tc1)
	assert_bool(mgr.check_military_victory(0)).is_false()
	# Destroy enemy TC
	mgr._on_building_destroyed(tc1)
	# Player 1 should be defeated, player 0 should win military
	assert_array(_defeated_ids).contains([1])
	assert_array(_victory_ids).contains([0])
	assert_array(_victory_conditions).contains(["military"])


func test_military_victory_not_triggered_with_remaining_enemy() -> void:
	var mgr := _create_manager()
	var tc0 := _create_tc(0)
	var tc1 := _create_tc(1, Vector2i(5, 5))
	var tc2 := _create_tc(2, Vector2i(10, 10))
	mgr.register_town_center(0, tc0)
	mgr.register_town_center(1, tc1)
	mgr.register_town_center(2, tc2)
	# Destroy player 1's TC
	mgr._on_building_destroyed(tc1)
	# Player 2 still alive so no military victory
	assert_bool(mgr.check_military_victory(0)).is_false()


func test_singularity_victory_at_age_6() -> void:
	var mgr := _create_manager()
	var tc0 := _create_tc(0)
	mgr.register_town_center(0, tc0)
	# Simulate reaching singularity age
	var old_age: int = GameManager.current_age
	GameManager.current_age = 6
	mgr.on_age_advanced(6)
	assert_array(_victory_ids).contains([0])
	assert_array(_victory_conditions).contains(["singularity"])
	# Restore
	GameManager.current_age = old_age


func test_singularity_victory_not_at_lower_age() -> void:
	var mgr := _create_manager()
	var old_age: int = GameManager.current_age
	GameManager.current_age = 5
	assert_bool(mgr.check_singularity_victory(0)).is_false()
	GameManager.current_age = old_age


func test_wonder_countdown_starts_and_completes() -> void:
	var mgr := _create_manager()
	mgr._wonder_countdown_duration = 5.0
	var tc0 := _create_tc(0)
	mgr.register_town_center(0, tc0)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)
	assert_array(_wonder_started_ids).contains([0])
	assert_float(mgr.get_wonder_countdown_remaining(0)).is_equal_approx(5.0, 0.1)
	# Simulate time passing (tick manually)
	mgr._tick_wonder_countdowns(5.1)
	assert_array(_victory_ids).contains([0])
	assert_array(_victory_conditions).contains(["wonder"])


func test_wonder_countdown_cancelled_on_destruction() -> void:
	var mgr := _create_manager()
	var tc0 := _create_tc(0)
	mgr.register_town_center(0, tc0)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)
	mgr.cancel_wonder_countdown(0)
	assert_array(_wonder_cancelled_ids).contains([0])
	assert_float(mgr.get_wonder_countdown_remaining(0)).is_equal(-1.0)
	# Tick should not trigger victory
	mgr._tick_wonder_countdowns(100.0)
	assert_array(_victory_ids).is_empty()


func test_multiple_victory_conditions_first_wins() -> void:
	var mgr := _create_manager()
	mgr._wonder_countdown_duration = 1.0
	var tc0 := _create_tc(0)
	var tc1 := _create_tc(1)
	mgr.register_town_center(0, tc0)
	mgr.register_town_center(1, tc1)
	# Trigger singularity first
	var old_age: int = GameManager.current_age
	GameManager.current_age = 6
	mgr.on_age_advanced(6)
	# Now try military — should not trigger because game is over
	mgr._on_building_destroyed(tc1)
	# Only singularity victory should have fired
	assert_int(_victory_ids.size()).is_equal(1)
	assert_str(_victory_conditions[0]).is_equal("singularity")
	GameManager.current_age = old_age


func test_defeated_player_cannot_win() -> void:
	var mgr := _create_manager()
	var tc0 := _create_tc(0)
	var tc1 := _create_tc(1)
	mgr.register_town_center(0, tc0)
	mgr.register_town_center(1, tc1)
	# Defeat player 0
	mgr._on_building_destroyed(tc0)
	assert_bool(mgr.check_military_victory(0)).is_false()
	assert_bool(mgr.check_singularity_victory(0)).is_false()


func test_save_load_roundtrip() -> void:
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)
	var state: Dictionary = mgr.save_state()
	assert_bool(state.has("game_over")).is_true()
	assert_bool(state.has("town_centers")).is_true()
	assert_bool(state.has("wonder_countdowns")).is_true()
	# Load into new manager
	var mgr2 := _create_manager()
	mgr2.load_state(state)
	assert_bool(mgr2.is_game_over()).is_false()
	# Wonder countdown should be restored
	assert_float(mgr2.get_wonder_countdown_remaining(0)).is_greater(-1.0)


func test_get_game_result_empty_before_end() -> void:
	var mgr := _create_manager()
	var result: Dictionary = mgr.get_game_result()
	assert_int(result.size()).is_equal(0)


func test_get_game_result_populated_after_victory() -> void:
	var mgr := _create_manager()
	var tc0 := _create_tc(0)
	var tc1 := _create_tc(1)
	mgr.register_town_center(0, tc0)
	mgr.register_town_center(1, tc1)
	mgr._on_building_destroyed(tc1)
	var result: Dictionary = mgr.get_game_result()
	assert_int(result.get("winner", -1)).is_equal(0)
	assert_str(result.get("condition", "")).is_equal("military")
	assert_bool(result.has("condition_label")).is_true()


func test_building_placed_signal_registers_tc() -> void:
	var placer := MockBuildingPlacer.new()
	add_child(placer)
	auto_free(placer)
	var mgr := _create_manager(placer)
	var tc := _create_tc(0)
	placer.building_placed.emit(tc)
	assert_bool(mgr.check_defeat(0)).is_false()


func test_defeat_delay_timer() -> void:
	var mgr := _create_manager()
	mgr._defeat_delay = 5.0
	var tc := _create_tc(1)
	mgr.register_town_center(1, tc)
	# Destroy TC — should not immediately defeat due to delay
	mgr._on_building_destroyed(tc)
	assert_array(_defeated_ids).is_empty()
	# Tick partial
	mgr._tick_defeat_timers(3.0)
	assert_array(_defeated_ids).is_empty()
	# Tick past delay
	mgr._tick_defeat_timers(3.0)
	assert_array(_defeated_ids).contains([1])
