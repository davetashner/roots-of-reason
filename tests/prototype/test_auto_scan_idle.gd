extends GdUnitTestSuite
## Tests for the auto-scan idle gate on defensive stance villagers.
## Verifies that auto-scan only triggers when the unit is truly idle,
## and that moving/gathering villagers are not interrupted by nearby wolves.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const CombatantScript := preload("res://scripts/prototype/combatant_component.gd")


func _create_villager(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "villager"
	unit.owner_id = 0
	unit.unit_category = "civilian"
	unit.hp = 25
	unit.max_hp = 25
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	return unit


func _create_wolf(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "wolf"
	unit.owner_id = -1
	unit.hp = 18
	unit.max_hp = 18
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	return unit


# -- Auto-scan idle gate --


func test_idle_villager_auto_scans_nearby_wolf() -> void:
	var villager := _create_villager(Vector2(100, 100))
	var wolf := _create_wolf(Vector2(200, 100))  # ~100px away, within 6 tiles
	# Ensure defensive stance with auto_scan
	villager._combatant.combat_config = {
		"stances": {"defensive": {"auto_scan": true, "pursue": false, "retaliate": true}},
		"scan_interval": 0.5,
		"aggro_scan_radius": 6,
		"leash_range": 8,
		"target_priority": {"melee": ["military", "civilian", "building"]},
	}
	villager._combatant.stance = CombatantScript.Stance.DEFENSIVE
	villager._combatant.scan_timer = 1.0  # Past interval — scan fires immediately
	# Villager is idle: not moving, not gathering, not building, not feeding
	assert_bool(villager.is_idle()).is_true()
	# Tick combat — should auto-scan and find the wolf
	villager._combatant.tick(0.1)
	assert_int(villager._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)
	assert_object(villager._combatant.combat_target).is_not_null()


func test_moving_villager_does_not_auto_scan() -> void:
	var villager := _create_villager(Vector2(100, 100))
	var wolf := _create_wolf(Vector2(200, 100))
	villager._combatant.combat_config = {
		"stances": {"defensive": {"auto_scan": true, "pursue": false, "retaliate": true}},
		"scan_interval": 0.5,
		"aggro_scan_radius": 6,
		"leash_range": 8,
		"target_priority": {"melee": ["military", "civilian", "building"]},
	}
	villager._combatant.stance = CombatantScript.Stance.DEFENSIVE
	villager._combatant.scan_timer = 1.0
	# Simulate player-commanded movement
	villager.move_to(Vector2(500, 100))
	assert_bool(villager._moving).is_true()
	assert_bool(villager.is_idle()).is_false()
	# Tick combat — should NOT auto-scan because unit is moving
	villager._combatant.tick(0.1)
	assert_int(villager._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)
	assert_object(villager._combatant.combat_target).is_null()


func test_moving_villager_still_retaliates_when_attacked() -> void:
	var villager := _create_villager(Vector2(100, 100))
	var wolf := _create_wolf(Vector2(150, 100))
	villager._combatant.combat_config = {
		"stances": {"defensive": {"auto_scan": true, "pursue": false, "retaliate": true}},
		"scan_interval": 0.5,
		"aggro_scan_radius": 6,
		"leash_range": 8,
		"target_priority": {"melee": ["military", "civilian", "building"]},
	}
	villager._combatant.stance = CombatantScript.Stance.DEFENSIVE
	# Villager is moving on player command
	villager.move_to(Vector2(500, 100))
	assert_bool(villager._moving).is_true()
	# Wolf attacks villager — retaliation should still work
	villager.take_damage(5, wolf)
	assert_int(villager._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)
	assert_object(villager._combatant.combat_target).is_same(wolf)


func test_assign_attack_target_overrides_movement() -> void:
	var villager := _create_villager(Vector2(100, 100))
	var wolf := _create_wolf(Vector2(300, 100))
	villager._combatant.combat_config = {
		"stances": {"defensive": {"auto_scan": true, "pursue": false, "retaliate": true}},
		"leash_range": 8,
	}
	# Villager is moving somewhere else
	villager.move_to(Vector2(500, 500))
	assert_bool(villager._moving).is_true()
	# Player right-clicks the wolf (attack command)
	villager.assign_attack_target(wolf)
	assert_int(villager._combatant.combat_state).is_equal(CombatantScript.CombatState.PURSUING)
	assert_object(villager._combatant.combat_target).is_same(wolf)


func test_villager_can_move_freely_past_wolf() -> void:
	var villager := _create_villager(Vector2(100, 100))
	var wolf := _create_wolf(Vector2(200, 100))
	villager._combatant.combat_config = {
		"stances": {"defensive": {"auto_scan": true, "pursue": false, "retaliate": true}},
		"scan_interval": 0.5,
		"aggro_scan_radius": 6,
		"leash_range": 8,
		"target_priority": {"melee": ["military", "civilian", "building"]},
	}
	villager._combatant.stance = CombatantScript.Stance.DEFENSIVE
	villager._combatant.scan_timer = 1.0
	# Player commands villager to move past the wolf
	var destination := Vector2(400, 100)
	villager.move_to(destination)
	# Tick multiple times — villager should keep moving, not divert to wolf
	for i in 5:
		villager._combatant.tick(0.5)
	assert_int(villager._combatant.combat_state).is_equal(CombatantScript.CombatState.NONE)
	assert_object(villager._combatant.combat_target).is_null()
	# Villager should still be heading to destination (still moving)
	assert_bool(villager._moving).is_true()
