extends GdUnitTestSuite
## Tests for prototype_unit.gd — build task and construction integration.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")


func _create_unit(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var u := Node2D.new()
	u.set_script(UnitScript)
	u.unit_type = "villager"
	u.position = pos
	u._build_speed = 1.0
	u._build_reach = 80.0
	add_child(u)
	auto_free(u)
	return u


func _create_building(pos: Vector2 = Vector2.ZERO, build_time: float = 25.0) -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = "house"
	b.max_hp = 550
	b.hp = 0
	b.under_construction = true
	b.build_progress = 0.0
	b._build_time = build_time
	b.footprint = Vector2i(2, 2)
	b.grid_pos = Vector2i(5, 5)
	b.position = pos
	add_child(b)
	auto_free(b)
	return b


# -- assign_build_target --


func test_assign_build_target_sets_target() -> void:
	var u := _create_unit()
	var b := _create_building(Vector2(50, 0))
	u.assign_build_target(b)
	assert_bool(u._build_target == b).is_true()


func test_assign_build_target_starts_moving() -> void:
	var u := _create_unit()
	var b := _create_building(Vector2(200, 0))
	u.assign_build_target(b)
	assert_bool(u._moving).is_true()


# -- _tick_build --


func test_tick_build_noop_when_no_target() -> void:
	var u := _create_unit()
	# Should not error when no target
	u._tick_build(1.0)
	assert_bool(u.is_idle()).is_true()


func test_tick_build_noop_when_out_of_range() -> void:
	var u := _create_unit(Vector2.ZERO)
	var b := _create_building(Vector2(500, 0))
	u._build_target = b
	u._moving = false
	u._tick_build(1.0)
	# Building progress should remain 0 (out of range)
	assert_float(b.build_progress).is_equal_approx(0.0, 0.001)


func test_tick_build_applies_work_in_range() -> void:
	var u := _create_unit(Vector2.ZERO)
	var b := _create_building(Vector2(30, 0), 25.0)
	u._build_target = b
	u._moving = false
	# 1 second of work: build_speed(1.0) / build_time(25.0) = 0.04
	u._tick_build(1.0)
	assert_float(b.build_progress).is_equal_approx(0.04, 0.001)


func test_tick_build_stops_movement_in_range() -> void:
	var u := _create_unit(Vector2.ZERO)
	var b := _create_building(Vector2(30, 0))
	u._build_target = b
	u._moving = true
	u._tick_build(1.0)
	assert_bool(u._moving).is_false()


func test_tick_build_clears_target_on_complete() -> void:
	var u := _create_unit(Vector2.ZERO)
	var b := _create_building(Vector2(30, 0), 1.0)
	u._build_target = b
	u._moving = false
	# build_speed(1.0) / build_time(1.0) * delta(1.0) = 1.0 => completes
	u._tick_build(1.0)
	assert_bool(u._build_target == null).is_true()
	assert_bool(b.under_construction).is_false()


func test_tick_build_clears_target_when_freed() -> void:
	var u := _create_unit(Vector2.ZERO)
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.under_construction = true
	b._build_time = 25.0
	b.max_hp = 100
	b.hp = 0
	add_child(b)
	u._build_target = b
	b.free()
	u._tick_build(1.0)
	assert_bool(u._build_target == null).is_true()


# -- is_idle --


func test_is_idle_when_stationary_no_target() -> void:
	var u := _create_unit()
	assert_bool(u.is_idle()).is_true()


func test_not_idle_when_moving() -> void:
	var u := _create_unit()
	u.move_to(Vector2(100, 100))
	assert_bool(u.is_idle()).is_false()


func test_not_idle_when_building() -> void:
	var u := _create_unit()
	var b := _create_building(Vector2(30, 0))
	u._build_target = b
	u._moving = false
	assert_bool(u.is_idle()).is_false()


# -- save_state --


func test_save_state_includes_build_target() -> void:
	var u := _create_unit()
	var b := _create_building()
	b.name = "Building_house_5_5"
	u._build_target = b
	var state: Dictionary = u.save_state()
	assert_str(state.get("build_target_name", "")).is_equal("Building_house_5_5")


func test_save_state_no_build_target() -> void:
	var u := _create_unit()
	var state: Dictionary = u.save_state()
	assert_bool(state.has("build_target_name")).is_false()


func test_load_state_stores_pending_target() -> void:
	var u := _create_unit()
	var state := {
		"position_x": 10.0,
		"position_y": 20.0,
		"unit_type": "villager",
		"build_target_name": "Building_house_5_5",
	}
	u.load_state(state)
	assert_str(u._pending_build_target_name).is_equal("Building_house_5_5")


# -- Multiple villagers additive --


func test_multiple_villagers_additive() -> void:
	var b := _create_building(Vector2.ZERO, 25.0)
	var u1 := _create_unit(Vector2(10, 0))
	var u2 := _create_unit(Vector2(-10, 0))
	var u3 := _create_unit(Vector2(0, 10))
	u1._build_target = b
	u2._build_target = b
	u3._build_target = b
	u1._moving = false
	u2._moving = false
	u3._moving = false
	# Each contributes 1.0/25.0 = 0.04 per second; 3 villagers = 0.12
	u1._tick_build(1.0)
	u2._tick_build(1.0)
	u3._tick_build(1.0)
	assert_float(b.build_progress).is_equal_approx(0.12, 0.001)


# -- Combat: attack speed, min-range, retaliation, death, building damage --


func _create_combat_unit(
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
	# Override stats/config after _ready() so DataLoader-less init is replaced
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
		"stances":
		{
			"aggressive": {"auto_scan": true, "pursue": true, "retaliate": true},
			"defensive": {"auto_scan": false, "pursue": false, "retaliate": true},
			"stand_ground": {"auto_scan": false, "pursue": false, "retaliate": false},
		},
	}
	return u


func test_attack_cooldown_uses_per_unit_attack_speed() -> void:
	var u := _create_combat_unit(Vector2.ZERO, "infantry", 0, {"attack_speed": 1.5})
	var enemy := _create_combat_unit(Vector2(30, 0), "infantry", 1)
	u._scene_root = self
	u._combat_target = enemy
	u._combat_state = u.CombatState.ATTACKING
	u._attack_cooldown = 0.0
	u._tick_combat(0.0)  # delta 0 just to trigger attack
	# After attacking, cooldown should be set to attack_speed (1.5)
	assert_float(u._attack_cooldown).is_equal_approx(1.5, 0.01)


func test_attack_cooldown_fallback_when_no_attack_speed() -> void:
	var u := _create_combat_unit(Vector2.ZERO, "infantry", 0, {"attack_speed": 0.0})
	var enemy := _create_combat_unit(Vector2(30, 0), "infantry", 1)
	u._scene_root = self
	u._combat_target = enemy
	u._combat_state = u.CombatState.ATTACKING
	u._attack_cooldown = 0.0
	u._tick_combat(0.0)
	# Should fall back to combat_config attack_cooldown (1.0)
	assert_float(u._attack_cooldown).is_equal_approx(1.0, 0.01)


func test_min_range_prevents_attack_on_adjacent_target() -> void:
	# Archer with min_range=1 (1 tile) should not attack unit right next to it
	var u := _create_combat_unit(
		Vector2.ZERO,
		"archer",
		0,
		{"range": 5, "min_range": 1, "attack_type": "ranged", "attack_speed": 2.0},
	)
	var enemy := _create_combat_unit(Vector2(10, 0), "infantry", 1)  # Very close
	u._scene_root = self
	u._combat_target = enemy
	u._combat_state = u.CombatState.ATTACKING
	u._attack_cooldown = 0.0
	u._tick_combat(0.0)
	# Should have disengaged — combat target cleared
	assert_that(u._combat_target).is_null()
	assert_int(u._combat_state).is_equal(u.CombatState.NONE)


func test_ranged_unit_attacks_at_valid_range() -> void:
	var tile_size: float = 64.0
	var u := _create_combat_unit(
		Vector2.ZERO,
		"archer",
		0,
		{"range": 5, "min_range": 1, "attack_type": "ranged", "attack_speed": 2.0},
	)
	# Place enemy at 3 tiles away — within range and beyond min_range
	var enemy := _create_combat_unit(Vector2(tile_size * 3, 0), "infantry", 1)
	u._scene_root = self
	u._combat_target = enemy
	u._combat_state = u.CombatState.ATTACKING
	u._attack_cooldown = 0.0
	u._tick_combat(0.0)
	# Should have attacked — cooldown set
	assert_float(u._attack_cooldown).is_greater(0.0)


func test_take_damage_triggers_retaliation() -> void:
	var u := _create_combat_unit(Vector2.ZERO, "infantry", 0)
	u._stance = u.Stance.DEFENSIVE  # Retaliates
	var attacker := _create_combat_unit(Vector2(30, 0), "infantry", 1)
	u._scene_root = self
	u.take_damage(5, attacker)
	assert_that(u._combat_target).is_equal(attacker)
	assert_int(u._combat_state).is_equal(u.CombatState.PURSUING)


func test_die_emits_signal() -> void:
	var u := _create_combat_unit(Vector2.ZERO, "infantry", 0)
	var result := [false]
	u.unit_died.connect(func(_unit: Node2D) -> void: result[0] = true)
	u._die()
	assert_bool(result[0]).is_true()


func test_save_load_attack_cooldown() -> void:
	var u := _create_combat_unit()
	u._attack_cooldown = 0.75
	var state: Dictionary = u.save_state()
	assert_float(float(state.get("attack_cooldown", 0.0))).is_equal_approx(0.75, 0.01)
	var u2 := _create_combat_unit()
	u2.load_state(state)
	assert_float(u2._attack_cooldown).is_equal_approx(0.75, 0.01)


func test_building_take_damage() -> void:
	var b := _create_building(Vector2.ZERO)
	b.under_construction = false
	b.build_progress = 1.0
	b.hp = 100
	b.max_hp = 100
	b.take_damage(30, null)
	assert_int(b.hp).is_equal(70)


func test_building_destruction_at_zero_hp() -> void:
	var b := _create_building(Vector2.ZERO)
	b.under_construction = false
	b.build_progress = 1.0
	b.hp = 10
	b.max_hp = 100
	b._combat_config = {"death_fade_duration": 0.0}
	var result := [false]
	b.building_destroyed.connect(func(_bld: Node2D) -> void: result[0] = true)
	b.take_damage(10, null)
	assert_bool(result[0]).is_true()
