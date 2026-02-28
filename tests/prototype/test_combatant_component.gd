extends GdUnitTestSuite
## Tests for CombatantComponent — combat state machine, stances, leashing,
## attack cooldown, and save/load round-trip.
##
## CombatantComponent is a RefCounted — tests instantiate it via a real
## prototype_unit node so all owner callbacks work correctly.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const CombatantScript := preload("res://scripts/prototype/combatant_component.gd")

var _default_combat_config: Dictionary = {
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


func _create_unit(
	pos: Vector2 = Vector2.ZERO,
	unit_type: String = "infantry",
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
	u.unit_type = unit_type
	u.unit_category = str(defaults.get("unit_category", "military"))
	u.owner_id = owner
	u.position = pos
	add_child(u)
	auto_free(u)
	# Override stats/config after _ready()
	u.stats = UnitStats.new(unit_type, defaults)
	u.hp = int(defaults["hp"])
	u.max_hp = int(defaults["hp"])
	u._combat_config = _default_combat_config.duplicate(true)
	u._scene_root = self
	return u


# ---------------------------------------------------------------------------
# CombatState transitions
# ---------------------------------------------------------------------------


func test_initial_state_is_none() -> void:
	var u := _create_unit()
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)


func test_engage_target_transitions_to_pursuing() -> void:
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(200, 0), "infantry", 1)
	u._combatant.engage_target(enemy)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)
	assert_object(u._combatant.combat_target).is_same(enemy)


func test_pursuing_transitions_to_attacking_when_in_range() -> void:
	# Place enemy within melee range (< 1 tile = 64px); range=0 means TILE_SIZE
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(50, 0), "infantry", 1)
	u._combatant.combat_state = CombatantScript.CombatState.PURSUING
	u._combatant.combat_target = enemy
	u._combatant.leash_origin = Vector2.ZERO
	u._combatant.tick(0.1)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.ATTACKING)


func test_attacking_returns_to_none_when_target_null() -> void:
	var u := _create_unit(Vector2.ZERO)
	u._combatant.combat_state = CombatantScript.CombatState.ATTACKING
	u._combatant.combat_target = null
	u._combatant.tick(0.1)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)


func test_attacking_transitions_back_to_pursuing_when_target_moves_away() -> void:
	# Enemy far enough away to trigger pursue (> range * 1.2)
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(400, 0), "infantry", 1)
	u._combatant.combat_state = CombatantScript.CombatState.ATTACKING
	u._combatant.combat_target = enemy
	# Aggressive stance has pursue=true
	u._combatant.stance = CombatantScript.Stance.AGGRESSIVE
	u._combatant.tick(0.1)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)


func test_cancel_resets_state_to_none() -> void:
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(200, 0), "infantry", 1)
	u._combatant.engage_target(enemy)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)
	u._combatant.cancel()
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)
	assert_object(u._combatant.combat_target).is_null()
	assert_float(u._combatant.attack_cooldown).is_equal(0.0)


# ---------------------------------------------------------------------------
# Stance behaviour
# ---------------------------------------------------------------------------


func test_aggressive_stance_auto_scans_when_idle() -> void:
	var u := _create_unit(Vector2(100, 100))
	var enemy := _create_unit(Vector2(200, 100), "infantry", 1)
	u._combatant.stance = CombatantScript.Stance.AGGRESSIVE
	u._combatant.scan_timer = 1.0  # past interval
	u._combatant.tick(0.1)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)


func test_defensive_stance_does_not_auto_scan() -> void:
	var u := _create_unit(Vector2(100, 100))
	# Add an enemy in range
	var enemy := _create_unit(Vector2(200, 100), "infantry", 1)
	u._combatant.stance = CombatantScript.Stance.DEFENSIVE
	u._combatant.scan_timer = 1.0
	u._combatant.tick(0.1)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)


func test_stand_ground_stance_does_not_auto_scan() -> void:
	var u := _create_unit(Vector2(100, 100))
	var enemy := _create_unit(Vector2(200, 100), "infantry", 1)
	u._combatant.stance = CombatantScript.Stance.STAND_GROUND
	u._combatant.scan_timer = 1.0
	u._combatant.tick(0.1)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)


func test_aggressive_stance_pursues_target_that_flees() -> void:
	# Aggressive has pursue=true — should follow target that left attack range
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(400, 0), "infantry", 1)
	u._combatant.stance = CombatantScript.Stance.AGGRESSIVE
	u._combatant.combat_state = CombatantScript.CombatState.ATTACKING
	u._combatant.combat_target = enemy
	u._combatant.tick(0.1)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)


func test_defensive_stance_drops_target_when_out_of_range() -> void:
	# Defensive has pursue=false — should drop target when out of range
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(400, 0), "infantry", 1)
	u._combatant.stance = CombatantScript.Stance.DEFENSIVE
	u._combatant.combat_state = CombatantScript.CombatState.ATTACKING
	u._combatant.combat_target = enemy
	u._combatant.tick(0.1)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)
	assert_object(u._combatant.combat_target).is_null()


func test_set_stance_stand_ground_cancels_pursuit() -> void:
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(200, 0), "infantry", 1)
	u._combatant.engage_target(enemy)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)
	u._combatant.set_stance(CombatantScript.Stance.STAND_GROUND)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)
	assert_object(u._combatant.combat_target).is_null()


func test_defensive_stance_retaliates_when_attacked() -> void:
	var u := _create_unit(Vector2(100, 100))
	var attacker := _create_unit(Vector2(150, 100), "infantry", 1)
	u._combatant.stance = CombatantScript.Stance.DEFENSIVE
	# take_damage triggers _try_retaliate
	u.take_damage(5, attacker)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)
	assert_object(u._combatant.combat_target).is_same(attacker)


func test_stand_ground_stance_does_not_retaliate() -> void:
	var u := _create_unit(Vector2(100, 100))
	var attacker := _create_unit(Vector2(150, 100), "infantry", 1)
	u._combatant.stance = CombatantScript.Stance.STAND_GROUND
	u.take_damage(5, attacker)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)
	assert_object(u._combatant.combat_target).is_null()


# ---------------------------------------------------------------------------
# Leash — return to origin after pursuit exceeds leash range
# ---------------------------------------------------------------------------


func test_leash_drops_target_and_returns_when_exceeded() -> void:
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(200, 0), "infantry", 1)
	u._combatant.combat_state = CombatantScript.CombatState.PURSUING
	u._combatant.combat_target = enemy
	# Place unit far beyond leash (8 tiles * 64px = 512px)
	u._combatant.leash_origin = Vector2.ZERO
	u.position = Vector2(600, 0)  # 600px from leash_origin > 512
	u._combatant.tick(0.1)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)
	assert_object(u._combatant.combat_target).is_null()


func test_leash_not_triggered_within_range() -> void:
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(100, 0), "infantry", 1)
	u._combatant.combat_state = CombatantScript.CombatState.PURSUING
	u._combatant.combat_target = enemy
	u._combatant.leash_origin = Vector2.ZERO
	# Unit is 100px from leash origin — well within 512px leash
	u._combatant.tick(0.1)
	# Should still be pursuing (not leashed out)
	assert_int(u._combatant.combat_state).is_not_equal(CombatantScript.CombatState.NONE)


func test_custom_leash_range_respected() -> void:
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(200, 0), "infantry", 1)
	# Override leash_range to 2 tiles = 128px
	var cfg := _default_combat_config.duplicate(true)
	cfg["leash_range"] = 2
	u._combatant.combat_config = cfg
	u._combatant.combat_state = CombatantScript.CombatState.PURSUING
	u._combatant.combat_target = enemy
	u._combatant.leash_origin = Vector2.ZERO
	u.position = Vector2(200, 0)  # 200px > 2*64=128 — exceeds leash
	u._combatant.tick(0.1)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)


# ---------------------------------------------------------------------------
# Attack cooldown
# ---------------------------------------------------------------------------


func test_attack_cooldown_decrements_each_tick() -> void:
	var u := _create_unit(Vector2.ZERO)
	u._combatant.attack_cooldown = 1.0
	# Tick with a dead target so no state changes interfere
	u._combatant.combat_state = CombatantScript.CombatState.NONE
	u._combatant.tick(0.3)
	assert_float(u._combatant.attack_cooldown).is_equal_approx(0.7, 0.001)


func test_attack_cooldown_does_not_go_below_zero_after_tick() -> void:
	var u := _create_unit(Vector2.ZERO)
	u._combatant.attack_cooldown = 0.1
	u._combatant.combat_state = CombatantScript.CombatState.NONE
	u._combatant.tick(0.5)
	assert_float(u._combatant.attack_cooldown).is_less_equal(0.0)


func test_attack_deals_damage_when_cooldown_ready() -> void:
	# Put attacker in ATTACKING state with target in melee range
	var u := _create_unit(Vector2.ZERO, "infantry", 0, {"attack": 10, "attack_speed": 1.0})
	var enemy := _create_unit(Vector2(50, 0), "infantry", 1, {"hp": 40, "defense": 0})
	u._combatant.combat_state = CombatantScript.CombatState.ATTACKING
	u._combatant.combat_target = enemy
	u._combatant.attack_cooldown = 0.0
	var hp_before: int = enemy.hp
	u._combatant.tick(0.1)
	assert_int(enemy.hp).is_less(hp_before)


func test_attack_does_not_deal_damage_while_on_cooldown() -> void:
	var u := _create_unit(Vector2.ZERO, "infantry", 0, {"attack": 10})
	var enemy := _create_unit(Vector2(50, 0), "infantry", 1, {"hp": 40, "defense": 0})
	u._combatant.combat_state = CombatantScript.CombatState.ATTACKING
	u._combatant.combat_target = enemy
	u._combatant.attack_cooldown = 5.0  # still on cooldown
	var hp_before: int = enemy.hp
	u._combatant.tick(0.1)
	assert_int(enemy.hp).is_equal(hp_before)


func test_cancel_resets_attack_cooldown() -> void:
	var u := _create_unit()
	u._combatant.attack_cooldown = 2.5
	u._combatant.cancel()
	assert_float(u._combatant.attack_cooldown).is_equal(0.0)


# ---------------------------------------------------------------------------
# Target assignment and cancellation
# ---------------------------------------------------------------------------


func test_engage_target_sets_leash_origin_to_current_position() -> void:
	var u := _create_unit(Vector2(128, 256))
	var enemy := _create_unit(Vector2(400, 256), "infantry", 1)
	u._combatant.engage_target(enemy)
	assert_that(u._combatant.leash_origin).is_equal(Vector2(128, 256))


func test_combat_target_cleared_when_target_hp_zero() -> void:
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(50, 0), "infantry", 1)
	u._combatant.combat_state = CombatantScript.CombatState.ATTACKING
	u._combatant.combat_target = enemy
	# Manually zero the enemy hp so tick() clears it
	enemy.hp = 0
	u._combatant.tick(0.1)
	assert_object(u._combatant.combat_target).is_null()


func test_combat_target_cleared_when_target_freed() -> void:
	var u := _create_unit(Vector2.ZERO)
	var enemy := Node2D.new()
	enemy.position = Vector2(50, 0)
	u._combatant.combat_state = CombatantScript.CombatState.ATTACKING
	u._combatant.combat_target = enemy
	# Free the node to invalidate it
	enemy.free()
	u._combatant.tick(0.1)
	assert_object(u._combatant.combat_target).is_null()


# ---------------------------------------------------------------------------
# Attack-move state
# ---------------------------------------------------------------------------


func test_attack_move_to_sets_attack_moving_state() -> void:
	var u := _create_unit(Vector2.ZERO)
	u._combatant.attack_move_to(Vector2(500, 0))
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.ATTACK_MOVING)
	assert_that(u._combatant.attack_move_destination).is_equal(Vector2(500, 0))


func test_attack_move_scans_for_targets() -> void:
	var u := _create_unit(Vector2(100, 100))
	var enemy := _create_unit(Vector2(200, 100), "infantry", 1)
	u._combatant.attack_move_to(Vector2(600, 100))
	u._combatant.scan_timer = 1.0  # past scan interval
	u._combatant.tick(0.1)
	# Should pick up the enemy and switch to pursuing
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)
	assert_object(u._combatant.combat_target).is_same(enemy)


# ---------------------------------------------------------------------------
# Patrol state
# ---------------------------------------------------------------------------


func test_patrol_between_sets_patrolling_state() -> void:
	var u := _create_unit(Vector2.ZERO)
	u._combatant.patrol_between(Vector2(0, 0), Vector2(500, 0))
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.PATROLLING)
	assert_that(u._combatant.patrol_point_a).is_equal(Vector2(0, 0))
	assert_that(u._combatant.patrol_point_b).is_equal(Vector2(500, 0))
	assert_bool(u._combatant.patrol_heading_to_b).is_true()


func test_patrolling_reverses_direction_at_waypoint() -> void:
	var u := _create_unit(Vector2(500, 0))
	u._combatant.patrol_between(Vector2(0, 0), Vector2(500, 0))
	# Simulate arriving at point b: unit is not moving
	u._moving = false
	u._combatant.patrol_heading_to_b = true  # was heading to b, arrived
	u._combatant.tick(0.1)
	assert_bool(u._combatant.patrol_heading_to_b).is_false()


# ---------------------------------------------------------------------------
# save_state / load_state round-trip
# ---------------------------------------------------------------------------


func test_save_state_preserves_combat_state() -> void:
	var u := _create_unit()
	u._combatant.combat_state = CombatantScript.CombatState.PURSUING
	var s: Dictionary = u._combatant.save_state()
	assert_int(int(s["combat_state"])).is_equal(CombatantScript.CombatState.PURSUING)


func test_save_state_preserves_stance() -> void:
	var u := _create_unit()
	u._combatant.stance = CombatantScript.Stance.DEFENSIVE
	var s: Dictionary = u._combatant.save_state()
	assert_int(int(s["stance"])).is_equal(CombatantScript.Stance.DEFENSIVE)


func test_save_state_preserves_attack_cooldown() -> void:
	var u := _create_unit()
	u._combatant.attack_cooldown = 0.75
	var s: Dictionary = u._combatant.save_state()
	assert_float(float(s["attack_cooldown"])).is_equal_approx(0.75, 0.001)


func test_save_state_preserves_attack_move_destination() -> void:
	var u := _create_unit()
	u._combatant.attack_move_to(Vector2(320, 128))
	var s: Dictionary = u._combatant.save_state()
	assert_float(float(s["attack_move_destination_x"])).is_equal_approx(320.0, 0.01)
	assert_float(float(s["attack_move_destination_y"])).is_equal_approx(128.0, 0.01)


func test_save_state_preserves_patrol_points() -> void:
	var u := _create_unit()
	u._combatant.patrol_between(Vector2(10, 20), Vector2(300, 400))
	var s: Dictionary = u._combatant.save_state()
	assert_float(float(s["patrol_point_a_x"])).is_equal_approx(10.0, 0.01)
	assert_float(float(s["patrol_point_a_y"])).is_equal_approx(20.0, 0.01)
	assert_float(float(s["patrol_point_b_x"])).is_equal_approx(300.0, 0.01)
	assert_float(float(s["patrol_point_b_y"])).is_equal_approx(400.0, 0.01)


func test_save_state_preserves_patrol_heading() -> void:
	var u := _create_unit()
	u._combatant.patrol_between(Vector2(0, 0), Vector2(200, 0))
	u._combatant.patrol_heading_to_b = false
	var s: Dictionary = u._combatant.save_state()
	assert_bool(bool(s["patrol_heading_to_b"])).is_false()


func test_save_state_includes_combat_target_name_when_set() -> void:
	var u := _create_unit(Vector2.ZERO)
	var enemy := _create_unit(Vector2(200, 0), "infantry", 1)
	enemy.name = "enemy_unit_1"
	u._combatant.combat_target = enemy
	var s: Dictionary = u._combatant.save_state()
	assert_str(str(s.get("combat_target_name", ""))).is_equal("enemy_unit_1")


func test_save_state_omits_combat_target_name_when_null() -> void:
	var u := _create_unit()
	u._combatant.combat_target = null
	var s: Dictionary = u._combatant.save_state()
	assert_bool(s.has("combat_target_name")).is_false()


func test_load_state_restores_combat_state() -> void:
	var u := _create_unit()
	var data: Dictionary = {"combat_state": CombatantScript.CombatState.ATTACKING}
	u._combatant.load_state(data)
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.ATTACKING)


func test_load_state_restores_stance() -> void:
	var u := _create_unit()
	var data: Dictionary = {"stance": CombatantScript.Stance.STAND_GROUND}
	u._combatant.load_state(data)
	assert_int(u._combatant.stance).is_equal(CombatantScript.Stance.STAND_GROUND)


func test_load_state_restores_attack_cooldown() -> void:
	var u := _create_unit()
	var data: Dictionary = {"attack_cooldown": 0.42}
	u._combatant.load_state(data)
	assert_float(u._combatant.attack_cooldown).is_equal_approx(0.42, 0.001)


func test_load_state_restores_patrol_points_and_heading() -> void:
	var u := _create_unit()
	var data: Dictionary = {
		"patrol_point_a_x": 10.0,
		"patrol_point_a_y": 20.0,
		"patrol_point_b_x": 300.0,
		"patrol_point_b_y": 400.0,
		"patrol_heading_to_b": false,
	}
	u._combatant.load_state(data)
	assert_that(u._combatant.patrol_point_a).is_equal(Vector2(10.0, 20.0))
	assert_that(u._combatant.patrol_point_b).is_equal(Vector2(300.0, 400.0))
	assert_bool(u._combatant.patrol_heading_to_b).is_false()


func test_load_state_defaults_when_keys_missing() -> void:
	var u := _create_unit()
	u._combatant.combat_state = CombatantScript.CombatState.PURSUING
	u._combatant.attack_cooldown = 3.0
	u._combatant.load_state({})
	assert_int(u._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)
	assert_float(u._combatant.attack_cooldown).is_equal(0.0)


func test_save_load_round_trip_preserves_all_fields() -> void:
	var u := _create_unit()
	# Set fields directly to avoid method side-effects overwriting combat_state
	u._combatant.combat_state = CombatantScript.CombatState.PATROLLING
	u._combatant.stance = CombatantScript.Stance.DEFENSIVE
	u._combatant.attack_cooldown = 0.33
	u._combatant.attack_move_destination = Vector2(100, 200)
	u._combatant.patrol_point_a = Vector2(10, 20)
	u._combatant.patrol_point_b = Vector2(30, 40)
	u._combatant.patrol_heading_to_b = false
	var saved: Dictionary = u._combatant.save_state()

	var u2 := _create_unit()
	u2._combatant.load_state(saved)
	assert_int(u2._combatant.combat_state).is_equal(CombatantScript.CombatState.PATROLLING)
	assert_int(u2._combatant.stance).is_equal(CombatantScript.Stance.DEFENSIVE)
	assert_float(u2._combatant.attack_cooldown).is_equal_approx(0.33, 0.001)
	assert_that(u2._combatant.attack_move_destination).is_equal(Vector2(100, 200))
	assert_that(u2._combatant.patrol_point_a).is_equal(Vector2(10, 20))
	assert_that(u2._combatant.patrol_point_b).is_equal(Vector2(30, 40))
	assert_bool(u2._combatant.patrol_heading_to_b).is_false()


func test_load_state_sets_pending_combat_target_name() -> void:
	var u := _create_unit()
	var data: Dictionary = {"combat_target_name": "some_enemy"}
	u._combatant.load_state(data)
	assert_str(u._combatant.pending_combat_target_name).is_equal("some_enemy")


func test_resolve_target_clears_pending_name() -> void:
	var u := _create_unit()
	var enemy := _create_unit(Vector2(200, 0), "infantry", 1)
	enemy.name = "target_node"
	# Simulate a saved target name that needs resolving
	u._combatant.pending_combat_target_name = "target_node"
	# resolve_target searches the scene root (self in tests is the suite node)
	# Add the enemy as a child of the test suite so get_node_or_null finds it
	add_child(enemy)
	u._combatant.resolve_target(self)
	assert_str(u._combatant.pending_combat_target_name).is_equal("")


func test_resolve_target_noop_when_name_empty() -> void:
	var u := _create_unit()
	u._combatant.pending_combat_target_name = ""
	u._combatant.combat_target = null
	u._combatant.resolve_target(self)
	assert_object(u._combatant.combat_target).is_null()
	assert_str(u._combatant.pending_combat_target_name).is_equal("")
