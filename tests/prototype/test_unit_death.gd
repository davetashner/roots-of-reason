extends GdUnitTestSuite
## Tests for unit death, corpse cleanup, and kill tracking (fk5.5).

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")
const TargetDetectorScript := preload("res://scripts/prototype/target_detector.gd")


func _create_unit(
	pos: Vector2 = Vector2.ZERO,
	type: String = "infantry",
	owner: int = 0,
	base_stats: Dictionary = {},
) -> Node2D:
	var defaults: Dictionary = {
		"hp": 40,
		"attack": 6,
		"defense": 1,
		"range": 0,
		"attack_speed": 1.5,
		"attack_type": "melee",
		"unit_category": "military",
	}
	for k in base_stats:
		defaults[k] = base_stats[k]
	var u := Node2D.new()
	u.set_script(UnitScript)
	u.unit_type = type
	u.unit_category = str(defaults.get("unit_category", "military"))
	u.owner_id = owner
	u.position = pos
	add_child(u)
	auto_free(u)
	# Override stats/config after _ready()
	u.stats = UnitStats.new(type, defaults)
	u.hp = int(defaults["hp"])
	u.max_hp = int(defaults["hp"])
	u._combat_config = {
		"attack_cooldown": 1.0,
		"aggro_scan_radius": 6,
		"scan_interval": 0.5,
		"leash_range": 8,
		"building_damage_reduction": 0.80,
		"show_damage_numbers": false,
		"death_fade_duration": 0.0,
		"attack_flash_duration": 0.0,
		"corpse_duration": 0.1,
		"corpse_modulate": [0.4, 0.4, 0.4, 0.5],
		"stances":
		{
			"aggressive": {"auto_scan": true, "pursue": true, "retaliate": true},
			"defensive": {"auto_scan": false, "pursue": false, "retaliate": true},
			"stand_ground": {"auto_scan": false, "pursue": false, "retaliate": false},
		},
	}
	return u


# -- Unit dies when HP reaches 0 --


func test_unit_dies_at_zero_hp() -> void:
	var u := _create_unit()
	var attacker := _create_unit(Vector2(30, 0), "infantry", 1)
	u.take_damage(u.hp, attacker)
	assert_int(u.hp).is_equal(0)
	assert_bool(u._is_dead).is_true()


func test_unit_dies_when_overkilled() -> void:
	var u := _create_unit()
	var attacker := _create_unit(Vector2(30, 0), "infantry", 1)
	u.take_damage(u.hp + 50, attacker)
	assert_int(u.hp).is_equal(0)
	assert_bool(u._is_dead).is_true()


# -- unit_died signal emitted with correct killer reference --


func test_unit_died_signal_emitted_with_killer() -> void:
	var u := _create_unit()
	var attacker := _create_unit(Vector2(30, 0), "infantry", 1)
	var result := [null, null]
	u.unit_died.connect(
		func(unit: Node2D, killer: Node2D) -> void:
			result[0] = unit
			result[1] = killer
	)
	u.take_damage(u.hp, attacker)
	assert_that(result[0]).is_equal(u)
	assert_that(result[1]).is_equal(attacker)


func test_unit_died_signal_null_killer_when_no_attacker() -> void:
	var u := _create_unit()
	var result := [null, "sentinel"]
	u.unit_died.connect(
		func(unit: Node2D, killer: Node2D) -> void:
			result[0] = unit
			result[1] = killer
	)
	u.take_damage(u.hp, null)
	assert_that(result[0]).is_equal(u)
	assert_that(result[1]).is_null()


# -- Dead unit is non-selectable --


func test_dead_unit_not_selectable() -> void:
	var u := _create_unit()
	u.take_damage(u.hp, null)
	u.select()
	assert_bool(u.selected).is_false()


func test_dead_unit_not_point_inside() -> void:
	var u := _create_unit()
	u.take_damage(u.hp, null)
	assert_bool(u.is_point_inside(u.global_position)).is_false()


# -- Kill count increments on kill --


func test_kill_count_increments_on_kill() -> void:
	var attacker := _create_unit(Vector2.ZERO, "infantry", 0, {"attack": 100})
	var victim := _create_unit(Vector2(30, 0), "infantry", 1, {"hp": 10})
	assert_int(attacker.kill_count).is_equal(0)
	victim.take_damage(victim.hp, attacker)
	assert_int(attacker.kill_count).is_equal(1)


func test_kill_count_accumulates_multiple_kills() -> void:
	var attacker := _create_unit(Vector2.ZERO, "infantry", 0, {"attack": 100})
	var v1 := _create_unit(Vector2(30, 0), "infantry", 1, {"hp": 10})
	var v2 := _create_unit(Vector2(60, 0), "infantry", 1, {"hp": 10})
	v1.take_damage(v1.hp, attacker)
	v2.take_damage(v2.hp, attacker)
	assert_int(attacker.kill_count).is_equal(2)


func test_kill_count_starts_at_zero() -> void:
	var u := _create_unit()
	assert_int(u.kill_count).is_equal(0)


# -- Corpse freed after duration --


func test_corpse_enters_corpse_state_after_death() -> void:
	var u := _create_unit()
	u.take_damage(u.hp, null)
	# With death_fade_duration = 0, corpse state is entered immediately
	# Modulate should reflect corpse appearance
	assert_float(u.modulate.r).is_equal_approx(0.4, 0.05)
	assert_float(u.modulate.g).is_equal_approx(0.4, 0.05)
	assert_float(u.modulate.b).is_equal_approx(0.4, 0.05)
	assert_float(u.modulate.a).is_equal_approx(0.5, 0.05)


# -- Population decremented on death --


func test_population_decremented_on_death() -> void:
	var pop := Node.new()
	pop.set_script(PopManagerScript)
	pop._hard_cap = 200
	pop._starting_cap = 10
	add_child(pop)
	auto_free(pop)
	var u := _create_unit()
	pop.register_unit(u, 0)
	assert_int(pop.get_population(0)).is_equal(1)
	# Simulate death handler
	pop.unregister_unit(u, 0)
	assert_int(pop.get_population(0)).is_equal(0)


func test_population_not_negative_after_multiple_unregister() -> void:
	var pop := Node.new()
	pop.set_script(PopManagerScript)
	pop._hard_cap = 200
	pop._starting_cap = 10
	add_child(pop)
	auto_free(pop)
	var u := _create_unit()
	pop.register_unit(u, 0)
	pop.unregister_unit(u, 0)
	pop.unregister_unit(u, 0)
	assert_int(pop.get_population(0)).is_equal(0)


# -- Save/load preserves kill_count --


func test_save_includes_kill_count() -> void:
	var u := _create_unit()
	u.kill_count = 5
	var state: Dictionary = u.save_state()
	assert_int(int(state.get("kill_count", 0))).is_equal(5)


func test_load_restores_kill_count() -> void:
	var u := _create_unit()
	var state := {"kill_count": 3, "position_x": 0.0, "position_y": 0.0, "unit_type": "infantry"}
	u.load_state(state)
	assert_int(u.kill_count).is_equal(3)


func test_load_defaults_kill_count_to_zero() -> void:
	var u := _create_unit()
	u.kill_count = 7
	var state := {"position_x": 0.0, "position_y": 0.0, "unit_type": "infantry"}
	u.load_state(state)
	assert_int(u.kill_count).is_equal(0)


# -- Target detector unregisters dead unit --


func test_target_detector_unregisters_on_death() -> void:
	var td := Node.new()
	td.set_script(TargetDetectorScript)
	add_child(td)
	auto_free(td)
	var u := _create_unit()
	td.register_entity(u)
	# Verify registered
	assert_that(td.detect(u.global_position)).is_equal(u)
	# Unregister (as prototype_main does on death)
	td.unregister_entity(u)
	assert_that(td.detect(u.global_position)).is_null()


# -- Dead unit ignores further damage --


func test_dead_unit_ignores_further_damage() -> void:
	var u := _create_unit()
	var attacker := _create_unit(Vector2(30, 0), "infantry", 1)
	u.take_damage(u.hp, attacker)
	assert_bool(u._is_dead).is_true()
	# Further damage should be ignored
	u.take_damage(10, attacker)
	assert_int(u.hp).is_equal(0)
	# Kill count should not double-increment
	assert_int(attacker.kill_count).is_equal(1)


# -- Die only happens once --


func test_die_only_fires_once() -> void:
	var u := _create_unit()
	var count := [0]
	u.unit_died.connect(func(_unit: Node2D, _killer: Node2D) -> void: count[0] += 1)
	u._die()
	u._die()
	assert_int(count[0]).is_equal(1)


# -- Dead unit process is stopped --


func test_dead_unit_process_stopped() -> void:
	var u := _create_unit()
	u.take_damage(u.hp, null)
	assert_bool(u.is_processing()).is_false()


# -- Combat state cancelled on death --


func test_combat_cancelled_on_death() -> void:
	var u := _create_unit()
	var enemy := _create_unit(Vector2(30, 0), "infantry", 1)
	u._combat_target = enemy
	u._combat_state = u.CombatState.ATTACKING
	u.take_damage(u.hp, enemy)
	assert_int(u._combat_state).is_equal(u.CombatState.NONE)
	assert_that(u._combat_target).is_null()
