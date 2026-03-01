extends GdUnitTestSuite
## Tests for scripts/prototype/population_manager.gd — population cap system.

const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")


func _create_manager(starting_cap: int = 5, hard_cap: int = 200) -> Node:
	var mgr := Node.new()
	mgr.set_script(PopManagerScript)
	add_child(mgr)
	# Override config after _ready() which may load from DataLoader
	mgr._starting_cap = starting_cap
	mgr._hard_cap = hard_cap
	return auto_free(mgr)


func _create_mock_building(bname: String = "house") -> Node2D:
	var b := Node2D.new()
	b.set_meta("building_name", bname)
	# Add building_name as a property via script override is not easy,
	# so we use a real building script.
	b.set_script(load("res://scripts/prototype/prototype_building.gd"))
	b.building_name = bname
	b.max_hp = 550
	b.hp = 550
	b.under_construction = false
	b.build_progress = 1.0
	b.footprint = Vector2i(2, 2)
	b.grid_pos = Vector2i(0, 0)
	add_child(b)
	return auto_free(b)


func _create_mock_unit(oid: int = 0) -> Node2D:
	var u := Node2D.new()
	u.set_script(load("res://scripts/prototype/prototype_unit.gd"))
	u.owner_id = oid
	add_child(u)
	return auto_free(u)


# --- Initial state ---


func test_initial_cap_equals_starting_cap() -> void:
	var mgr := _create_manager(5)
	assert_int(mgr.get_population_cap(0)).is_equal(5)


func test_initial_population_is_zero() -> void:
	var mgr := _create_manager()
	assert_int(mgr.get_population(0)).is_equal(0)


# --- Building registration ---


func test_register_building_increases_cap() -> void:
	var mgr := _create_manager(5)
	var house := _create_mock_building("house")
	mgr.register_building(house, 0)
	assert_int(mgr.get_population_cap(0)).is_equal(15)


func test_unregister_building_decreases_cap() -> void:
	var mgr := _create_manager(5)
	var house := _create_mock_building("house")
	mgr.register_building(house, 0)
	assert_int(mgr.get_population_cap(0)).is_equal(15)
	mgr.unregister_building(house, 0)
	assert_int(mgr.get_population_cap(0)).is_equal(5)


func test_cap_clamped_to_hard_cap() -> void:
	var mgr := _create_manager(5, 20)
	# Add 5 houses = 5 + 50 = 55, but clamped to 20
	for i in 5:
		var house := _create_mock_building("house")
		mgr.register_building(house, 0)
	assert_int(mgr.get_population_cap(0)).is_equal(20)


# --- Unit registration ---


func test_register_unit_increases_population() -> void:
	var mgr := _create_manager()
	var unit := _create_mock_unit()
	mgr.register_unit(unit, 0)
	assert_int(mgr.get_population(0)).is_equal(1)


func test_unregister_unit_decreases_population() -> void:
	var mgr := _create_manager()
	var unit := _create_mock_unit()
	mgr.register_unit(unit, 0)
	mgr.unregister_unit(unit, 0)
	assert_int(mgr.get_population(0)).is_equal(0)


func test_unregister_unit_does_not_go_below_zero() -> void:
	var mgr := _create_manager()
	var unit := _create_mock_unit()
	mgr.unregister_unit(unit, 0)
	assert_int(mgr.get_population(0)).is_equal(0)


# --- Training checks ---


func test_can_train_when_under_cap() -> void:
	var mgr := _create_manager(5)
	assert_bool(mgr.can_train(0, 1)).is_true()


func test_cannot_train_when_at_cap() -> void:
	var mgr := _create_manager(5)
	for i in 5:
		var unit := _create_mock_unit()
		mgr.register_unit(unit, 0)
	assert_bool(mgr.can_train(0, 1)).is_false()


func test_cannot_train_when_over_cap() -> void:
	var mgr := _create_manager(5)
	# Add units + 1 house to get cap 15, then remove house
	var house := _create_mock_building("house")
	mgr.register_building(house, 0)
	for i in 8:
		var unit := _create_mock_unit()
		mgr.register_unit(unit, 0)
	# Now at 8/15, remove house -> cap goes to 5, population 8
	mgr.unregister_building(house, 0)
	assert_int(mgr.get_population(0)).is_equal(8)
	assert_int(mgr.get_population_cap(0)).is_equal(5)
	assert_bool(mgr.can_train(0, 1)).is_false()


func test_can_train_with_pop_cost() -> void:
	var mgr := _create_manager(5)
	for i in 3:
		var unit := _create_mock_unit()
		mgr.register_unit(unit, 0)
	# 3/5 cap, cost 2 -> 3+2=5 <= 5 -> true
	assert_bool(mgr.can_train(0, 2)).is_true()
	# 3/5 cap, cost 3 -> 3+3=6 > 5 -> false
	assert_bool(mgr.can_train(0, 3)).is_false()


# --- Near cap warning ---


func test_is_near_cap_within_threshold() -> void:
	var mgr := _create_manager(5)
	for i in 4:
		var unit := _create_mock_unit()
		mgr.register_unit(unit, 0)
	# 4/5, diff = 1, threshold = 2 -> near
	assert_bool(mgr.is_near_cap(0, 2)).is_true()


func test_is_near_cap_not_near() -> void:
	var mgr := _create_manager(10, 200)
	var unit := _create_mock_unit()
	mgr.register_unit(unit, 0)
	# 1/10, diff = 9, threshold = 2 -> not near
	assert_bool(mgr.is_near_cap(0, 2)).is_false()


func test_is_near_cap_at_cap_is_false() -> void:
	var mgr := _create_manager(5)
	for i in 5:
		var unit := _create_mock_unit()
		mgr.register_unit(unit, 0)
	# 5/5, current == cap -> is_near_cap should be false (already at cap)
	assert_bool(mgr.is_near_cap(0, 2)).is_false()


# --- Signals ---


func test_population_changed_signal_emitted_on_register_unit() -> void:
	var mgr := _create_manager(5)
	var monitor := monitor_signals(mgr)
	var unit := _create_mock_unit()
	mgr.register_unit(unit, 0)
	await assert_signal(monitor).is_emitted("population_changed", [0, 1, 5])


func test_population_changed_signal_emitted_on_register_building() -> void:
	var mgr := _create_manager(5)
	var monitor := monitor_signals(mgr)
	var house := _create_mock_building("house")
	mgr.register_building(house, 0)
	await assert_signal(monitor).is_emitted("population_changed", [0, 0, 15])


func test_near_cap_warning_signal_emitted() -> void:
	var mgr := _create_manager(5)
	var monitor := monitor_signals(mgr)
	for i in 3:
		var unit := _create_mock_unit()
		mgr.register_unit(unit, 0)
	# At 3/5, not near yet. Add one more -> 4/5, within threshold of 2
	var unit := _create_mock_unit()
	mgr.register_unit(unit, 0)
	await assert_signal(monitor).is_emitted("near_cap_warning", [0])


# --- Save/Load ---


func test_save_load_preserves_state() -> void:
	var mgr := _create_manager(5, 200)
	var house := _create_mock_building("house")
	mgr.register_building(house, 0)
	for i in 3:
		var unit := _create_mock_unit()
		mgr.register_unit(unit, 0)
	var state: Dictionary = mgr.save_state()
	# Create a new manager and load
	var mgr2 := _create_manager(10, 100)  # Different defaults
	mgr2.load_state(state)
	assert_int(mgr2.get_population(0)).is_equal(3)
	assert_int(mgr2.get_population_cap(0)).is_equal(15)
	assert_int(mgr2._hard_cap).is_equal(200)
	assert_int(mgr2._starting_cap).is_equal(5)


func test_starting_cap_from_config() -> void:
	# This test verifies the manager respects the starting_cap value.
	# In test context, _load_config may not find DataLoader, so we verify
	# the default is used and can be overridden.
	var mgr := _create_manager(5)
	assert_int(mgr.get_population_cap(0)).is_equal(5)
	var mgr2 := _create_manager(10)
	assert_int(mgr2.get_population_cap(0)).is_equal(10)


# --- Building count tracking ---


func test_building_count_tracks_all_buildings() -> void:
	var mgr := _create_manager(5)
	var house := _create_mock_building("house")
	var barracks := _create_mock_building("barracks")
	mgr.register_building(house, 0)
	mgr.register_building(barracks, 0)
	assert_int(mgr.get_building_count(0)).is_equal(2)


func test_unregister_decrements_building_count() -> void:
	var mgr := _create_manager(5)
	var house := _create_mock_building("house")
	mgr.register_building(house, 0)
	assert_int(mgr.get_building_count(0)).is_equal(1)
	mgr.unregister_building(house, 0)
	assert_int(mgr.get_building_count(0)).is_equal(0)


func test_building_count_changed_signal_emitted() -> void:
	var mgr := _create_manager(5)
	var monitor := monitor_signals(mgr)
	var house := _create_mock_building("house")
	mgr.register_building(house, 0)
	await assert_signal(monitor).is_emitted("building_count_changed", [0, 1])


# --- Housing tech bonus ---


func test_apply_housing_tech_bonus_increases_cap() -> void:
	var mgr := _create_manager(5)
	var house1 := _create_mock_building("house")
	var house2 := _create_mock_building("house")
	mgr.register_building(house1, 0)
	mgr.register_building(house2, 0)
	# 5 + 10*2 = 25
	assert_int(mgr.get_population_cap(0)).is_equal(25)
	# Apply +5 per house tech bonus: 5 + 10*2 + 5*2 = 35
	mgr.apply_housing_tech_bonus(0, 5)
	assert_int(mgr.get_population_cap(0)).is_equal(35)


func test_housing_tech_bonus_applies_to_new_buildings() -> void:
	var mgr := _create_manager(5)
	var house1 := _create_mock_building("house")
	mgr.register_building(house1, 0)
	mgr.apply_housing_tech_bonus(0, 5)
	# 5 + 10 + 5*1 = 20
	assert_int(mgr.get_population_cap(0)).is_equal(20)
	# Build another house: 5 + 10*2 + 5*2 = 35
	var house2 := _create_mock_building("house")
	mgr.register_building(house2, 0)
	assert_int(mgr.get_population_cap(0)).is_equal(35)


func test_on_tech_researched_with_house_capacity() -> void:
	var mgr := _create_manager(5)
	var house := _create_mock_building("house")
	mgr.register_building(house, 0)
	# 5 + 10 = 15
	assert_int(mgr.get_population_cap(0)).is_equal(15)
	var effects: Dictionary = {"economic_bonus": {"house_capacity": 5}}
	mgr._on_tech_researched(0, "engineering", effects)
	# 5 + 10 + 5*1 = 20
	assert_int(mgr.get_population_cap(0)).is_equal(20)


func test_on_tech_researched_ignores_unrelated_effects() -> void:
	var mgr := _create_manager(5)
	var house := _create_mock_building("house")
	mgr.register_building(house, 0)
	var effects: Dictionary = {"economic_bonus": {"gather_rate": 0.10}}
	mgr._on_tech_researched(0, "stone_tools", effects)
	# Should remain unchanged: 5 + 10 = 15
	assert_int(mgr.get_population_cap(0)).is_equal(15)


func test_save_load_preserves_housing_tech_bonus() -> void:
	var mgr := _create_manager(5, 200)
	var house := _create_mock_building("house")
	mgr.register_building(house, 0)
	mgr.apply_housing_tech_bonus(0, 5)
	# 5 + 10 + 5*1 = 20
	assert_int(mgr.get_population_cap(0)).is_equal(20)
	var state: Dictionary = mgr.save_state()
	var mgr2 := _create_manager(10, 100)
	mgr2.load_state(state)
	assert_int(mgr2._housing_tech_bonus.get(0, 0)).is_equal(5)
