extends GdUnitTestSuite
## Tests for unit_upgrade_manager.gd — tech stat_modifiers → UnitStats wiring.

const UnitUpgradeManagerScript := preload("res://scripts/prototype/unit_upgrade_manager.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")


func _create_manager() -> Node:
	var node := Node.new()
	node.set_script(UnitUpgradeManagerScript)
	add_child(node)
	auto_free(node)
	return node


func _create_unit(unit_type: String, owner_id: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = unit_type
	unit.owner_id = owner_id
	add_child(unit)
	auto_free(unit)
	return unit


func _create_unit_stub(unit_type: String, owner_id: int = 0) -> Node2D:
	## Creates a minimal unit with stats but without full prototype_unit setup.
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = unit_type
	unit.owner_id = owner_id
	add_child(unit)
	auto_free(unit)
	return unit


func _bronze_working_effects() -> Dictionary:
	return {"stat_modifiers": {"melee_attack": 1}}


func _iron_working_effects() -> Dictionary:
	return {"stat_modifiers": {"melee_attack": 2}}


func _fletching_effects() -> Dictionary:
	return {"stat_modifiers": {"ranged_attack": 0.30}}


# -- Basic application --


func test_on_tech_researched_applies_modifier() -> void:
	var mgr := _create_manager()
	var scene_root := Node.new()
	add_child(scene_root)
	auto_free(scene_root)
	mgr.setup(scene_root)
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "infantry"
	unit.owner_id = 0
	scene_root.add_child(unit)
	auto_free(unit)
	var base_attack: float = unit.stats.get_stat("attack")
	mgr.on_tech_researched(0, "bronze_working", _bronze_working_effects())
	var new_attack: float = unit.stats.get_stat("attack")
	assert_float(new_attack).is_equal(base_attack + 1.0)


func test_modifier_applies_to_correct_unit_types() -> void:
	var mgr := _create_manager()
	var scene_root := Node.new()
	add_child(scene_root)
	auto_free(scene_root)
	mgr.setup(scene_root)
	var infantry := Node2D.new()
	infantry.set_script(UnitScript)
	infantry.unit_type = "infantry"
	infantry.owner_id = 0
	scene_root.add_child(infantry)
	auto_free(infantry)
	var archer := Node2D.new()
	archer.set_script(UnitScript)
	archer.unit_type = "archer"
	archer.owner_id = 0
	scene_root.add_child(archer)
	auto_free(archer)
	var archer_base: float = archer.stats.get_stat("attack")
	mgr.on_tech_researched(0, "bronze_working", _bronze_working_effects())
	# melee_attack should NOT apply to archer
	assert_bool(archer.stats.has_modifier("attack", "tech:bronze_working")).is_false()
	assert_float(archer.stats.get_stat("attack")).is_equal(archer_base)
	# melee_attack SHOULD apply to infantry
	assert_bool(infantry.stats.has_modifier("attack", "tech:bronze_working")).is_true()


func test_percent_modifier_applies_correctly() -> void:
	var mgr := _create_manager()
	var scene_root := Node.new()
	add_child(scene_root)
	auto_free(scene_root)
	mgr.setup(scene_root)
	var archer := Node2D.new()
	archer.set_script(UnitScript)
	archer.unit_type = "archer"
	archer.owner_id = 0
	scene_root.add_child(archer)
	auto_free(archer)
	var base_attack: float = archer.stats.get_stat("attack")
	mgr.on_tech_researched(0, "fletching", _fletching_effects())
	# ranged_attack is percent type: (base) * (1 + 0.30)
	var expected: float = base_attack * 1.30
	assert_float(archer.stats.get_stat("attack")).is_equal_approx(expected, 0.01)


# -- Regression --


func test_on_tech_regressed_removes_modifier() -> void:
	var mgr := _create_manager()
	var scene_root := Node.new()
	add_child(scene_root)
	auto_free(scene_root)
	mgr.setup(scene_root)
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "infantry"
	unit.owner_id = 0
	scene_root.add_child(unit)
	auto_free(unit)
	var base_attack: float = unit.stats.get_stat("attack")
	mgr.on_tech_researched(0, "bronze_working", _bronze_working_effects())
	assert_float(unit.stats.get_stat("attack")).is_equal(base_attack + 1.0)
	mgr.on_tech_regressed(0, "bronze_working", {})
	assert_float(unit.stats.get_stat("attack")).is_equal(base_attack)
	assert_bool(unit.stats.has_modifier("attack", "tech:bronze_working")).is_false()


# -- New unit replay --


func test_apply_upgrades_to_new_unit() -> void:
	var mgr := _create_manager()
	var scene_root := Node.new()
	add_child(scene_root)
	auto_free(scene_root)
	mgr.setup(scene_root)
	# Research tech before unit exists
	mgr.on_tech_researched(0, "bronze_working", _bronze_working_effects())
	# New unit spawns
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "infantry"
	unit.owner_id = 0
	scene_root.add_child(unit)
	auto_free(unit)
	var base_attack: float = unit.stats.get_base_stat("attack")
	mgr.apply_upgrades_to_unit(unit, 0)
	assert_float(unit.stats.get_stat("attack")).is_equal(base_attack + 1.0)


# -- Stacking --


func test_multiple_techs_stack() -> void:
	var mgr := _create_manager()
	var scene_root := Node.new()
	add_child(scene_root)
	auto_free(scene_root)
	mgr.setup(scene_root)
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "infantry"
	unit.owner_id = 0
	scene_root.add_child(unit)
	auto_free(unit)
	var base_attack: float = unit.stats.get_stat("attack")
	mgr.on_tech_researched(0, "bronze_working", _bronze_working_effects())
	mgr.on_tech_researched(0, "iron_working", _iron_working_effects())
	# Both flat +1 and +2 should stack
	assert_float(unit.stats.get_stat("attack")).is_equal(base_attack + 3.0)


# -- Unmapped key --


func test_unmapped_modifier_key_ignored() -> void:
	var mgr := _create_manager()
	var scene_root := Node.new()
	add_child(scene_root)
	auto_free(scene_root)
	mgr.setup(scene_root)
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "infantry"
	unit.owner_id = 0
	scene_root.add_child(unit)
	auto_free(unit)
	# building_hp is not in the modifier_map — should be silently ignored
	var effects: Dictionary = {"stat_modifiers": {"building_hp": 100}}
	mgr.on_tech_researched(0, "masonry", effects)
	# No crash, no modifiers added
	assert_bool(unit.stats.has_modifier("hp", "tech:masonry")).is_false()


# -- Save/load --


func test_save_state_includes_applied_upgrades() -> void:
	var mgr := _create_manager()
	var scene_root := Node.new()
	add_child(scene_root)
	auto_free(scene_root)
	mgr.setup(scene_root)
	mgr.on_tech_researched(0, "bronze_working", _bronze_working_effects())
	var state: Dictionary = mgr.save_state()
	assert_bool(state.has("applied_upgrades")).is_true()
	assert_bool(state["applied_upgrades"].has("0")).is_true()
	var entries: Array = state["applied_upgrades"]["0"]
	assert_int(entries.size()).is_equal(1)
	assert_str(entries[0]["tech_id"]).is_equal("bronze_working")


func test_load_state_restores_applied_upgrades() -> void:
	var mgr := _create_manager()
	var scene_root := Node.new()
	add_child(scene_root)
	auto_free(scene_root)
	mgr.setup(scene_root)
	mgr.on_tech_researched(0, "bronze_working", _bronze_working_effects())
	var state: Dictionary = mgr.save_state()
	# Create new manager and load state
	var mgr2 := _create_manager()
	mgr2.setup(scene_root)
	mgr2.load_state(state)
	# Apply to a new unit — should get the upgrade
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "infantry"
	unit.owner_id = 0
	scene_root.add_child(unit)
	auto_free(unit)
	var base_attack: float = unit.stats.get_base_stat("attack")
	mgr2.apply_upgrades_to_unit(unit, 0)
	assert_float(unit.stats.get_stat("attack")).is_equal(base_attack + 1.0)


# -- Player isolation --


func test_no_effect_on_wrong_player() -> void:
	var mgr := _create_manager()
	var scene_root := Node.new()
	add_child(scene_root)
	auto_free(scene_root)
	mgr.setup(scene_root)
	var p0_unit := Node2D.new()
	p0_unit.set_script(UnitScript)
	p0_unit.unit_type = "infantry"
	p0_unit.owner_id = 0
	scene_root.add_child(p0_unit)
	auto_free(p0_unit)
	var p1_unit := Node2D.new()
	p1_unit.set_script(UnitScript)
	p1_unit.unit_type = "infantry"
	p1_unit.owner_id = 1
	scene_root.add_child(p1_unit)
	auto_free(p1_unit)
	var p1_base: float = p1_unit.stats.get_stat("attack")
	# Player 0 researches — should not affect player 1
	mgr.on_tech_researched(0, "bronze_working", _bronze_working_effects())
	assert_bool(p1_unit.stats.has_modifier("attack", "tech:bronze_working")).is_false()
	assert_float(p1_unit.stats.get_stat("attack")).is_equal(p1_base)
