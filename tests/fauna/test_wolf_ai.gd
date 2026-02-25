extends GdUnitTestSuite
## Tests for wolf_ai.gd — wolf fauna AI state machine.

const WolfAIScript := preload("res://scripts/fauna/wolf_ai.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")

var _cfg: Dictionary = {
	"patrol_radius_tiles": 8,
	"patrol_idle_min": 3.0,
	"patrol_idle_max": 5.0,
	"aggro_radius_tiles": 3,
	"aggro_unit_categories": ["civilian"],
	"flee_military_radius_tiles": 5,
	"flee_military_count_threshold": 3,
	"flee_military_radius_during_attack_tiles": 4,
	"flee_military_during_attack_count": 2,
	"flee_duration": 5.0,
	"flee_distance_tiles": 10,
	"chase_abandon_distance_tiles": 6,
	"pack_cohesion_max_tiles": 4,
	"attack_speed_pixels": 192.0,
	"patrol_speed_pixels": 96.0,
	"scan_interval": 0.5,
	"carcass_resource_name": "wolf_carcass",
}


func _create_wolf(pos: Vector2 = Vector2.ZERO, pid: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "wolf"
	unit.owner_id = -1
	unit.unit_color = Color(0.5, 0.5, 0.5)
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	var ai := Node.new()
	ai.name = "WolfAI"
	ai.set_script(WolfAIScript)
	ai.pack_id = pid
	unit.add_child(ai)
	# Manually set config since DataLoader may not be available
	ai._cfg = _cfg
	ai.spawn_origin = pos
	ai._scene_root = self
	return unit


func _get_ai(unit: Node2D) -> Node:
	return unit.get_node("WolfAI")


func _create_civilian(pos: Vector2 = Vector2.ZERO, owner: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "villager"
	unit.owner_id = owner
	unit.unit_category = "civilian"
	unit.hp = 25
	unit.max_hp = 25
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	return unit


func _create_military(pos: Vector2 = Vector2.ZERO, owner: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "infantry"
	unit.owner_id = owner
	unit.unit_category = "military"
	unit.hp = 40
	unit.max_hp = 40
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	return unit


# -- Init tests --


func test_starts_in_patrol_state() -> void:
	var wolf := _create_wolf()
	var ai := _get_ai(wolf)
	assert_int(ai._state).is_equal(WolfAIScript.WolfState.PATROL)


func test_stance_is_stand_ground() -> void:
	var wolf := _create_wolf()
	assert_int(wolf._stance).is_equal(UnitScript.Stance.STAND_GROUND)


func test_spawn_origin_set() -> void:
	var wolf := _create_wolf(Vector2(100, 200))
	var ai := _get_ai(wolf)
	assert_bool(ai.spawn_origin == Vector2(100, 200)).is_true()


# -- PATROL tests --


func test_moves_after_idle_timer() -> void:
	var wolf := _create_wolf(Vector2(200, 200))
	var ai := _get_ai(wolf)
	ai._patrol_idle_timer = 0.1
	ai._is_moving = false
	# Tick past idle timer
	ai._tick_patrol(0.2)
	# After idle expires, a new patrol target should be picked
	assert_bool(ai._is_moving).is_true()


func test_stays_within_patrol_radius() -> void:
	var origin := Vector2(500, 500)
	var wolf := _create_wolf(origin)
	var ai := _get_ai(wolf)
	var radius: float = float(_cfg["patrol_radius_tiles"]) * WolfAIScript.TILE_SIZE
	# Pick patrol target many times and verify all are within bounds
	for i in 20:
		ai._pick_patrol_target()
		var dist: float = ai._move_target.distance_to(origin)
		# Allow some slack for pack cohesion adjustment
		assert_float(dist).is_less(radius * 2.0)


# -- Aggro tests --


func test_aggros_civilian_in_range() -> void:
	var wolf := _create_wolf(Vector2(100, 100))
	var ai := _get_ai(wolf)
	# Place civilian within aggro range (3 tiles = 192 pixels)
	var civ := _create_civilian(Vector2(200, 100))
	assert_object(civ).is_not_null()
	var target: Node2D = ai._scan_for_aggro_target()
	assert_object(target).is_not_null()


func test_ignores_military_for_aggro() -> void:
	var wolf := _create_wolf(Vector2(100, 100))
	var ai := _get_ai(wolf)
	# Place military within aggro range — should not aggro
	var mil := _create_military(Vector2(200, 100))
	assert_object(mil).is_not_null()
	var target: Node2D = ai._scan_for_aggro_target()
	assert_object(target).is_null()


func test_ignores_unit_outside_aggro_radius() -> void:
	var wolf := _create_wolf(Vector2(100, 100))
	var ai := _get_ai(wolf)
	# Place civilian far outside aggro range (3 tiles = 192px)
	var civ := _create_civilian(Vector2(1000, 100))
	assert_object(civ).is_not_null()
	var target: Node2D = ai._scan_for_aggro_target()
	assert_object(target).is_null()


# -- ATTACK tests --


func test_transitions_to_attack_on_aggro() -> void:
	var wolf := _create_wolf(Vector2(100, 100))
	var ai := _get_ai(wolf)
	var civ := _create_civilian(Vector2(200, 100))
	ai._enter_attack(civ)
	assert_int(ai._state).is_equal(WolfAIScript.WolfState.ATTACK)
	assert_object(ai._combat_target).is_same(civ)


func test_alerts_packmates_on_attack() -> void:
	var wolf1 := _create_wolf(Vector2(100, 100), 0)
	var wolf2 := _create_wolf(Vector2(150, 100), 0)
	var ai1 := _get_ai(wolf1)
	var ai2 := _get_ai(wolf2)
	# Manually link pack members
	ai1._pack_members.append(ai2)
	ai2._pack_members.append(ai1)
	var civ := _create_civilian(Vector2(200, 100))
	ai1._enter_attack(civ)
	# Packmate should also be in ATTACK
	assert_int(ai2._state).is_equal(WolfAIScript.WolfState.ATTACK)


func test_abandons_if_target_dies() -> void:
	var wolf := _create_wolf(Vector2(100, 100))
	var ai := _get_ai(wolf)
	var civ := _create_civilian(Vector2(150, 100))
	ai._enter_attack(civ)
	# Simulate target death
	civ.hp = 0
	ai._tick_attack(0.1)
	assert_int(ai._state).is_equal(WolfAIScript.WolfState.PATROL)


func test_abandons_if_target_beyond_chase_range() -> void:
	var wolf := _create_wolf(Vector2(100, 100))
	var ai := _get_ai(wolf)
	var civ := _create_civilian(Vector2(150, 100))
	ai._enter_attack(civ)
	# Move target far away (beyond 6 tiles = 384px)
	civ.position = Vector2(600, 100)
	ai._tick_attack(0.1)
	assert_int(ai._state).is_equal(WolfAIScript.WolfState.PATROL)


# -- FLEE tests --


func test_flees_from_military_group_in_patrol() -> void:
	var wolf := _create_wolf(Vector2(300, 300))
	var ai := _get_ai(wolf)
	# Place 3 military units nearby (threshold = 3)
	for i in 3:
		_create_military(Vector2(300 + i * 20, 300))
	assert_bool(ai._should_flee_military()).is_true()


func test_flees_from_military_during_attack() -> void:
	var wolf := _create_wolf(Vector2(300, 300))
	var ai := _get_ai(wolf)
	# Place 2 military units nearby (during-attack threshold = 2)
	for i in 2:
		_create_military(Vector2(300 + i * 20, 300))
	assert_bool(ai._should_flee_military_during_attack()).is_true()


func test_flee_timer_expires_to_patrol() -> void:
	var wolf := _create_wolf(Vector2(300, 300))
	var ai := _get_ai(wolf)
	ai._enter_flee()
	assert_int(ai._state).is_equal(WolfAIScript.WolfState.FLEE)
	# Tick past flee duration
	ai._flee_timer = 0.05
	ai._tick_flee(0.1)
	assert_int(ai._state).is_equal(WolfAIScript.WolfState.PATROL)


# -- Pack death test --


func test_packmate_death_triggers_flee() -> void:
	var wolf1 := _create_wolf(Vector2(100, 100), 0)
	var wolf2 := _create_wolf(Vector2(150, 100), 0)
	var ai1 := _get_ai(wolf1)
	var ai2 := _get_ai(wolf2)
	ai1._pack_members.append(ai2)
	ai2._pack_members.append(ai1)
	# wolf1 dies
	ai1._on_wolf_died(wolf1)
	# Packmate should flee
	assert_int(ai2._state).is_equal(WolfAIScript.WolfState.FLEE)


# -- Save/Load test --


func test_save_load_round_trip() -> void:
	var wolf := _create_wolf(Vector2(200, 300))
	var ai := _get_ai(wolf)
	ai._state = WolfAIScript.WolfState.FLEE
	ai.pack_id = 5
	ai._flee_timer = 3.2
	ai._is_moving = true
	ai._move_target = Vector2(400, 500)
	var data: Dictionary = ai.save_state()
	# Create a fresh wolf and load state
	var wolf2 := _create_wolf()
	var ai2 := _get_ai(wolf2)
	ai2.load_state(data)
	assert_int(ai2._state).is_equal(WolfAIScript.WolfState.FLEE)
	assert_int(ai2.pack_id).is_equal(5)
	assert_float(ai2._flee_timer).is_equal_approx(3.2, 0.01)
	assert_bool(ai2._is_moving).is_true()
	assert_bool(ai2._move_target == Vector2(400, 500)).is_true()
	assert_bool(ai2.spawn_origin == Vector2(200, 300)).is_true()
