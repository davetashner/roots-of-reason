extends GdUnitTestSuite
## Tests for pirate_ai.gd — pirate ship AI state machine.

const PirateAIScript := preload("res://scripts/fauna/pirate_ai.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")

var _cfg: Dictionary = {
	"scan_interval": 0.5,
	"targets": ["fishing_boat", "trade_barge", "transport_ship"],
	"avoids": ["war_galley", "warship", "dock_with_garrison"],
	"stats":
	{
		"hp": 80,
		"attack": 12,
		"defense": 3,
		"speed": 3.0,
		"range": 4,
		"los": 6,
	},
	"bounty":
	{
		"min_gold": 30,
		"max_gold": 120,
		"scaling_by_age": {"3": 1.0, "4": 1.5, "5": 2.0, "6": 0.5},
	},
	"spawn_rate_by_age": {"3": 1.0, "4": 0.8, "5": 0.5, "6": 0.2},
}


func _create_pirate(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "pirate_ship"
	unit.owner_id = -1
	unit.entity_category = "pirate"
	unit.position = pos
	unit.hp = 80
	unit.max_hp = 80
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	var ai := Node.new()
	ai.name = "PirateAI"
	ai.set_script(PirateAIScript)
	unit.add_child(ai)
	# Manually set config since DataLoader may not be available
	ai._cfg = _cfg
	ai.spawn_origin = pos
	ai._scene_root = self
	return unit


func _get_ai(unit: Node2D) -> Node:
	return unit.get_node("PirateAI")


func _create_target(pos: Vector2 = Vector2.ZERO, utype: String = "fishing_boat", owner: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = utype
	unit.owner_id = owner
	unit.hp = 40
	unit.max_hp = 40
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	return unit


func _create_warship(pos: Vector2 = Vector2.ZERO, owner: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "war_galley"
	unit.owner_id = owner
	unit.unit_category = "military"
	unit.hp = 120
	unit.max_hp = 120
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	return unit


# -- Init tests --


func test_starts_in_patrol_state() -> void:
	var pirate := _create_pirate()
	var ai := _get_ai(pirate)
	assert_int(ai._state).is_equal(PirateAIScript.PirateState.PATROL)


func test_spawn_origin_set() -> void:
	var pirate := _create_pirate(Vector2(200, 300))
	var ai := _get_ai(pirate)
	assert_float(ai.spawn_origin.x).is_equal_approx(200.0, 0.1)
	assert_float(ai.spawn_origin.y).is_equal_approx(300.0, 0.1)


# -- Patrol tests --


func test_patrol_moves_unit_from_spawn() -> void:
	var pirate := _create_pirate(Vector2(100, 100))
	var ai := _get_ai(pirate)
	# Force past idle timer
	ai._patrol_idle_timer = 0.0
	ai._process(0.1)
	# Should have picked a patrol target and started moving
	assert_bool(ai._is_moving).is_true()


# -- Target detection --


func test_detects_fishing_boat_transitions_to_hunt() -> void:
	var pirate := _create_pirate(Vector2(100, 100))
	var ai := _get_ai(pirate)
	# Place fishing boat within LOS (6 tiles * 64 = 384)
	_create_target(Vector2(200, 100), "fishing_boat")
	# Trigger scan
	ai._scan_timer = 1.0
	ai._process(0.1)
	(
		assert_int(ai._state)
		. is_in(
			[
				PirateAIScript.PirateState.HUNT,
				PirateAIScript.PirateState.ATTACK,
			]
		)
	)


func test_ignores_non_target_units() -> void:
	var pirate := _create_pirate(Vector2(100, 100))
	var ai := _get_ai(pirate)
	# Place a villager nearby — not in targets list
	_create_target(Vector2(200, 100), "villager")
	# Trigger scan
	ai._scan_timer = 1.0
	ai._process(0.1)
	assert_int(ai._state).is_equal(PirateAIScript.PirateState.PATROL)


# -- Flee tests --


func test_detects_war_galley_transitions_to_flee() -> void:
	var pirate := _create_pirate(Vector2(100, 100))
	var ai := _get_ai(pirate)
	# Place war galley within LOS
	_create_warship(Vector2(200, 100))
	# Trigger scan
	ai._scan_timer = 1.0
	ai._process(0.1)
	assert_int(ai._state).is_equal(PirateAIScript.PirateState.FLEE)


func test_flee_direction_away_from_threat() -> void:
	var pirate := _create_pirate(Vector2(300, 300))
	var ai := _get_ai(pirate)
	# War galley to the right
	_create_warship(Vector2(400, 300))
	ai._scan_timer = 1.0
	ai._process(0.1)
	# Move target should be to the left (away from threat)
	assert_float(ai._move_target.x).is_less(300.0)


func test_returns_to_patrol_after_flee_duration() -> void:
	var pirate := _create_pirate(Vector2(100, 100))
	var ai := _get_ai(pirate)
	ai._state = PirateAIScript.PirateState.FLEE
	ai._flee_timer = 0.01
	ai._is_moving = false
	ai._process(0.1)
	assert_int(ai._state).is_equal(PirateAIScript.PirateState.PATROL)


# -- Attack tests --


func test_deals_damage_when_in_range() -> void:
	var pirate := _create_pirate(Vector2(100, 100))
	var ai := _get_ai(pirate)
	# Place fishing boat within attack range (4 tiles * 64 = 256)
	var target := _create_target(Vector2(150, 100), "fishing_boat")
	var initial_hp: int = target.hp
	# Set up attack state
	ai._state = PirateAIScript.PirateState.ATTACK
	ai._combat_target = target
	pirate._attack_cooldown = 0.0
	# Process multiple ticks
	for i in 5:
		ai._process(0.1)
	assert_int(target.hp).is_less(initial_hp)


# -- Chase abandon --


func test_abandons_chase_beyond_max_distance() -> void:
	var pirate := _create_pirate(Vector2(100, 100))
	var ai := _get_ai(pirate)
	# Target far away — beyond 2x LOS (2 * 6 * 64 = 768)
	var target := _create_target(Vector2(1000, 100), "fishing_boat")
	ai._state = PirateAIScript.PirateState.HUNT
	ai._combat_target = target
	ai._process(0.1)
	assert_int(ai._state).is_equal(PirateAIScript.PirateState.PATROL)


# -- Save / Load --


func test_save_load_round_trip() -> void:
	var pirate := _create_pirate(Vector2(50, 75))
	var ai := _get_ai(pirate)
	ai._state = PirateAIScript.PirateState.FLEE
	ai._flee_timer = 3.5
	ai._is_moving = true
	ai._move_target = Vector2(200, 300)
	var saved: Dictionary = ai.save_state()
	# Create fresh pirate and load state
	var pirate2 := _create_pirate(Vector2.ZERO)
	var ai2 := _get_ai(pirate2)
	ai2.load_state(saved)
	assert_int(ai2._state).is_equal(PirateAIScript.PirateState.FLEE)
	assert_float(ai2._flee_timer).is_equal_approx(3.5, 0.01)
	assert_bool(ai2._is_moving).is_true()
	assert_float(ai2._move_target.x).is_equal_approx(200.0, 0.1)
	assert_float(ai2._move_target.y).is_equal_approx(300.0, 0.1)
	assert_float(ai2.spawn_origin.x).is_equal_approx(50.0, 0.1)
	assert_float(ai2.spawn_origin.y).is_equal_approx(75.0, 0.1)
