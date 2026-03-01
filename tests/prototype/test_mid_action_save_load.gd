extends GdUnitTestSuite
## Tests for mid-action save/load round-trips.
## Verifies that units saved while actively gathering (GATHERING state) or
## pursuing a combat target (PURSUING state) correctly restore their state
## after load_state + resolve_target.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const CombatantScript := preload("res://scripts/prototype/combatant_component.gd")
const GathererScript := preload("res://scripts/prototype/gatherer_component.gd")
const UnitFactory := preload("res://tests/helpers/unit_factory.gd")
const ResourceFactory := preload("res://tests/helpers/resource_factory.gd")

var _root: Node2D


func before_test() -> void:
	_root = Node2D.new()
	_root.name = "TestRoot"
	add_child(_root)
	auto_free(_root)


func _create_unit(
	uname: String = "Unit_0",
	utype: String = "villager",
	pos: Vector2 = Vector2.ZERO,
) -> Node2D:
	var u := UnitFactory.create_villager({name = uname, unit_type = utype, position = pos, scene_root = _root})
	_root.add_child(u)
	auto_free(u)
	return u


func _create_enemy(uname: String = "Enemy_0", pos: Vector2 = Vector2(200, 0)) -> Node2D:
	var u := (
		UnitFactory
		. create_villager(
			{
				name = uname,
				unit_type = "land",
				owner_id = 1,
				position = pos,
				hp = 50,
				max_hp = 50,
				scene_root = _root,
			}
		)
	)
	_root.add_child(u)
	auto_free(u)
	return u


func _create_resource(
	rname: String = "Resource_food_0",
	pos: Vector2 = Vector2(30, 0),
	res_type: String = "food",
	yield_amt: int = 150,
) -> Node2D:
	var n := ResourceFactory.create_resource_node(
		{name = rname, position = pos, resource_type = res_type, total_yield = yield_amt}
	)
	_root.add_child(n)
	auto_free(n)
	return n


# -- Mid-gather save/load --


func test_save_mid_gather_captures_gathering_state() -> void:
	var u := _create_unit("Villager_0", "villager", Vector2(30, 0))
	var res := _create_resource("Resource_food_0", Vector2(30, 0))
	u.assign_gather_target(res)
	u._moving = false
	u._gather_state = UnitScript.GatherState.GATHERING
	u._carried_amount = 3
	u._gather_accumulator = 0.7

	var state: Dictionary = u.save_state()

	assert_int(int(state.get("gather_state", -1))).is_equal(UnitScript.GatherState.GATHERING)
	assert_str(str(state.get("gather_target_name", ""))).is_equal("Resource_food_0")
	assert_int(int(state.get("carried_amount", 0))).is_equal(3)
	assert_float(float(state.get("gather_accumulator", 0.0))).is_equal_approx(0.7, 0.01)
	assert_str(str(state.get("gather_type", ""))).is_equal("food")


func test_load_mid_gather_restores_state_before_resolve() -> void:
	var u2 := _create_unit("Villager_1", "villager")
	var state := {
		"position_x": 30.0,
		"position_y": 0.0,
		"unit_type": "villager",
		"gather_state": UnitScript.GatherState.GATHERING,
		"gather_type": "food",
		"carried_amount": 3,
		"gather_accumulator": 0.7,
		"gather_target_name": "Resource_food_0",
	}

	u2.load_state(state)

	# Before resolve_gather_target, target node is not yet linked but pending name is set
	assert_int(u2._gather_state).is_equal(UnitScript.GatherState.GATHERING)
	assert_str(u2._gather_type).is_equal("food")
	assert_int(u2._carried_amount).is_equal(3)
	assert_float(u2._gather_accumulator).is_equal_approx(0.7, 0.01)
	assert_str(u2._pending_gather_target_name).is_equal("Resource_food_0")
	assert_object(u2._gather_target).is_null()


func test_resolve_gather_target_links_node_after_load() -> void:
	var res := _create_resource("Resource_wood_0", Vector2(50, 0), "wood")
	var u2 := _create_unit("Villager_2", "villager")
	var state := {
		"position_x": 50.0,
		"position_y": 0.0,
		"unit_type": "villager",
		"gather_state": UnitScript.GatherState.GATHERING,
		"gather_type": "wood",
		"carried_amount": 5,
		"gather_accumulator": 0.2,
		"gather_target_name": "Resource_wood_0",
	}

	u2.load_state(state)
	u2.resolve_gather_target(_root)

	# After resolve, the actual gather_target node should be linked
	assert_object(u2._gather_target).is_not_null()
	assert_bool(u2._gather_target == res).is_true()
	# pending name should be cleared
	assert_str(u2._pending_gather_target_name).is_equal("")


func test_mid_gather_round_trip_preserves_accumulator_and_carry() -> void:
	# Full save → load → resolve round-trip for a gathering villager
	var res := _create_resource("Resource_stone_0", Vector2(40, 0), "stone", 200)
	var u1 := _create_unit("Villager_3", "villager", Vector2(40, 0))
	u1.assign_gather_target(res)
	u1._moving = false
	u1._gather_state = UnitScript.GatherState.GATHERING
	u1._carried_amount = 6
	u1._gather_accumulator = 0.55

	var state: Dictionary = u1.save_state()

	var u2 := _create_unit("Villager_4", "villager")
	u2.load_state(state)
	u2.resolve_gather_target(_root)

	assert_int(u2._gather_state).is_equal(UnitScript.GatherState.GATHERING)
	assert_int(u2._carried_amount).is_equal(6)
	assert_float(u2._gather_accumulator).is_equal_approx(0.55, 0.01)
	assert_bool(u2._gather_target == res).is_true()
	assert_str(u2._gather_type).is_equal("stone")


func test_mid_gather_moving_to_resource_state_preserved() -> void:
	# Unit saved while still moving to resource (not yet gathering)
	var res := _create_resource("Resource_gold_0", Vector2(100, 0), "gold", 100)
	var u1 := _create_unit("Villager_5", "villager", Vector2.ZERO)
	u1.assign_gather_target(res)
	# Unit is en-route; still in MOVING_TO_RESOURCE
	assert_int(u1._gather_state).is_equal(UnitScript.GatherState.MOVING_TO_RESOURCE)

	var state: Dictionary = u1.save_state()

	var u2 := _create_unit("Villager_6", "villager")
	u2.load_state(state)
	u2.resolve_gather_target(_root)

	assert_int(u2._gather_state).is_equal(UnitScript.GatherState.MOVING_TO_RESOURCE)
	assert_bool(u2._gather_target == res).is_true()


# -- Mid-combat save/load (PURSUING state) --


func test_save_mid_combat_pursuing_captures_target_name() -> void:
	var attacker := _create_unit("Attacker_0", "villager", Vector2.ZERO)
	var enemy := _create_enemy("Enemy_0", Vector2(200, 0))
	attacker.assign_attack_target(enemy)

	assert_int(attacker._combat_state).is_equal(UnitScript.CombatState.PURSUING)

	var state: Dictionary = attacker.save_state()

	assert_int(int(state.get("combat_state", -1))).is_equal(UnitScript.CombatState.PURSUING)
	assert_str(str(state.get("combat_target_name", ""))).is_equal("Enemy_0")


func test_load_mid_combat_pursuing_sets_pending_name() -> void:
	var u2 := _create_unit("Attacker_1", "villager")
	var state := {
		"position_x": 0.0,
		"position_y": 0.0,
		"unit_type": "villager",
		"combat_state": UnitScript.CombatState.PURSUING,
		"combat_target_name": "Enemy_0",
	}

	u2.load_state(state)

	assert_int(u2._combat_state).is_equal(UnitScript.CombatState.PURSUING)
	assert_str(u2._pending_combat_target_name).is_equal("Enemy_0")
	# Target node not yet resolved
	assert_object(u2._combat_target).is_null()


func test_resolve_combat_target_links_node_after_load() -> void:
	var enemy := _create_enemy("Enemy_1", Vector2(300, 0))
	var u2 := _create_unit("Attacker_2", "villager")
	var state := {
		"position_x": 0.0,
		"position_y": 0.0,
		"unit_type": "villager",
		"combat_state": UnitScript.CombatState.PURSUING,
		"combat_target_name": "Enemy_1",
	}

	u2.load_state(state)
	u2.resolve_combat_target(_root)

	assert_object(u2._combat_target).is_not_null()
	assert_bool(u2._combat_target == enemy).is_true()
	assert_str(u2._pending_combat_target_name).is_equal("")


func test_mid_combat_round_trip_preserves_pursuing_state() -> void:
	# Full save → load → resolve round-trip for a unit in PURSUING state
	var attacker := _create_unit("Attacker_3", "villager", Vector2.ZERO)
	var enemy := _create_enemy("Enemy_2", Vector2(150, 0))
	attacker.assign_attack_target(enemy)
	attacker._combatant.attack_cooldown = 0.5
	assert_int(attacker._combat_state).is_equal(UnitScript.CombatState.PURSUING)

	var state: Dictionary = attacker.save_state()

	var u2 := _create_unit("Attacker_4", "villager")
	u2.load_state(state)
	u2.resolve_combat_target(_root)

	assert_int(u2._combat_state).is_equal(UnitScript.CombatState.PURSUING)
	assert_bool(u2._combat_target == enemy).is_true()
	assert_float(u2._attack_cooldown).is_equal_approx(0.5, 0.01)


func test_resolve_combat_target_clears_pending_when_node_missing() -> void:
	# If the target node no longer exists in the scene, pending should clear gracefully
	var u2 := _create_unit("Attacker_5", "villager")
	var state := {
		"position_x": 0.0,
		"position_y": 0.0,
		"unit_type": "villager",
		"combat_state": UnitScript.CombatState.PURSUING,
		"combat_target_name": "GhostEnemy_99",
	}

	u2.load_state(state)
	u2.resolve_combat_target(_root)

	# combat_target should stay null — node not found
	assert_object(u2._combat_target).is_null()
	# pending name must be cleared to avoid repeated lookup attempts
	assert_str(u2._pending_combat_target_name).is_equal("")
	# combat_state should remain as loaded (caller must decide whether to reset)
	assert_int(u2._combat_state).is_equal(UnitScript.CombatState.PURSUING)


func test_resolve_gather_target_clears_pending_when_node_missing() -> void:
	# If the resource node no longer exists, pending should clear gracefully
	var u2 := _create_unit("Villager_7", "villager")
	var state := {
		"position_x": 0.0,
		"position_y": 0.0,
		"unit_type": "villager",
		"gather_state": UnitScript.GatherState.GATHERING,
		"gather_type": "food",
		"carried_amount": 2,
		"gather_accumulator": 0.1,
		"gather_target_name": "Resource_ghost_99",
	}

	u2.load_state(state)
	u2.resolve_gather_target(_root)

	# gather_target should stay null
	assert_object(u2._gather_target).is_null()
	# pending name must be cleared
	assert_str(u2._pending_gather_target_name).is_equal("")
	# other fields should still be intact
	assert_int(u2._gather_state).is_equal(UnitScript.GatherState.GATHERING)
	assert_int(u2._carried_amount).is_equal(2)


# -- Combat stance preserved across save/load --


func test_stance_preserved_across_round_trip() -> void:
	var u1 := _create_unit("Attacker_6", "villager", Vector2.ZERO)
	u1._combatant.stance = CombatantScript.Stance.DEFENSIVE

	var state: Dictionary = u1.save_state()

	var u2 := _create_unit("Attacker_7", "villager")
	u2.load_state(state)

	assert_int(u2._stance).is_equal(UnitScript.Stance.DEFENSIVE)


func test_attack_cooldown_preserved_across_round_trip() -> void:
	var u1 := _create_unit("Attacker_8", "villager", Vector2.ZERO)
	u1._combatant.attack_cooldown = 0.75

	var state: Dictionary = u1.save_state()

	var u2 := _create_unit("Attacker_9", "villager")
	u2.load_state(state)

	assert_float(u2._attack_cooldown).is_equal_approx(0.75, 0.01)
