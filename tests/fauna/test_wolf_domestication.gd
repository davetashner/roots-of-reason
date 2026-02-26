extends GdUnitTestSuite
## Tests for wolf domestication — feeding, progress, decay, aggro suppression.

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
	"feed_distance_tiles": 2,
	"feed_duration": 5.0,
	"feed_cooldown_per_wolf": 5.0,
}


func _create_wolf(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "wolf"
	unit.owner_id = -1
	unit.unit_color = Color(0.5, 0.5, 0.5)
	unit.position = pos
	unit.hp = 30
	unit.max_hp = 30
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	var ai := Node.new()
	ai.name = "WolfAI"
	ai.set_script(WolfAIScript)
	unit.add_child(ai)
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


# -- begin_feeding tests --


func test_begin_feeding_enters_being_fed() -> void:
	var wolf := _create_wolf()
	var ai := _get_ai(wolf)
	var feeder := _create_civilian()
	var result: bool = ai.begin_feeding(feeder, 0)
	assert_bool(result).is_true()
	assert_int(ai._state).is_equal(WolfAIScript.WolfState.BEING_FED)
	assert_object(ai._current_feeder).is_same(feeder)


# -- complete_feeding tests --


func test_complete_feeding_adds_progress() -> void:
	var wolf := _create_wolf()
	var ai := _get_ai(wolf)
	var feeder := _create_civilian()
	ai.begin_feeding(feeder, 0)
	ai.complete_feeding()
	# 1.0 / 3.0 ≈ 0.333
	assert_float(ai._domestication_progress).is_greater(0.3)
	assert_float(ai._domestication_progress).is_less(0.4)


func test_three_feedings_triggers_domesticated() -> void:
	var wolf := _create_wolf()
	var ai := _get_ai(wolf)
	var result := {"emitted": false, "owner_id": -1}
	ai.domesticated.connect(
		func(oid: int) -> void:
			result["emitted"] = true
			result["owner_id"] = oid
	)
	for i in 3:
		var feeder := _create_civilian()
		ai._feed_lockout_timer = 0.0
		ai.begin_feeding(feeder, 0)
		ai.complete_feeding()
	assert_int(ai._state).is_equal(WolfAIScript.WolfState.DOMESTICATED)
	assert_float(ai._domestication_progress).is_equal_approx(1.0, 0.01)
	assert_bool(result["emitted"]).is_true()
	assert_int(result["owner_id"]).is_equal(0)


# -- Contested feeding --


func test_contested_feeding_resets_progress() -> void:
	var wolf := _create_wolf()
	var ai := _get_ai(wolf)
	var feeder1 := _create_civilian(Vector2.ZERO, 0)
	ai.begin_feeding(feeder1, 0)
	ai.complete_feeding()
	var old_progress: float = ai._domestication_progress
	assert_float(old_progress).is_greater(0.0)
	# Different player feeds — resets progress
	var feeder2 := _create_civilian(Vector2.ZERO, 1)
	ai._feed_lockout_timer = 0.0
	ai.begin_feeding(feeder2, 1)
	assert_float(ai._domestication_progress).is_equal(0.0)
	assert_int(ai._domestication_owner_id).is_equal(1)


# -- Damage interruption --


func test_feeding_interrupted_by_damage() -> void:
	var wolf := _create_wolf()
	var ai := _get_ai(wolf)
	var feeder := _create_civilian()
	ai.begin_feeding(feeder, 0)
	# Simulate damage: lower wolf HP
	wolf.hp = 20
	ai._tick_being_fed(0.1)
	assert_int(ai._state).is_equal(WolfAIScript.WolfState.FLEE)
	assert_object(ai._current_feeder).is_null()


# -- Decay --


func test_decay_reduces_progress() -> void:
	var wolf := _create_wolf()
	var ai := _get_ai(wolf)
	var feeder := _create_civilian()
	ai.begin_feeding(feeder, 0)
	ai.complete_feeding()
	var progress_before: float = ai._domestication_progress
	# Manually tick decay — simulate elapsed time beyond decay interval
	# Default decay_interval=60, decay_rate=0.1 from wolf.json
	# We don't have DataLoader in tests, so _load_wolf_data returns {}
	# Defaults: interval=60, rate=0.1
	ai._decay_timer = 59.9
	ai._tick_domestication_decay(0.2)
	assert_float(ai._domestication_progress).is_less(progress_before)


# -- Feed lockout --


func test_feed_lockout_prevents_feeding() -> void:
	var wolf := _create_wolf()
	var ai := _get_ai(wolf)
	var feeder := _create_civilian()
	# Set lockout timer
	ai._feed_lockout_timer = 3.0
	var result: bool = ai.begin_feeding(feeder, 0)
	assert_bool(result).is_false()
	assert_int(ai._state).is_equal(WolfAIScript.WolfState.PATROL)


# -- Save/Load --


func test_save_load_preserves_domestication() -> void:
	var wolf := _create_wolf(Vector2(100, 200))
	var ai := _get_ai(wolf)
	var feeder := _create_civilian()
	ai.begin_feeding(feeder, 0)
	ai.complete_feeding()
	ai._decay_timer = 15.0
	ai._feed_lockout_timer = 2.5
	var data: Dictionary = ai.save_state()
	var wolf2 := _create_wolf()
	var ai2 := _get_ai(wolf2)
	ai2.load_state(data)
	assert_float(ai2._domestication_progress).is_equal_approx(ai._domestication_progress, 0.01)
	assert_int(ai2._domestication_owner_id).is_equal(0)
	assert_float(ai2._decay_timer).is_equal_approx(15.0, 0.01)
	assert_float(ai2._feed_lockout_timer).is_equal_approx(2.5, 0.01)


# -- Aggro suppression --


func test_aggro_suppressed_against_feeder() -> void:
	var wolf := _create_wolf(Vector2(100, 100))
	var ai := _get_ai(wolf)
	# Place civilian within aggro range
	var feeder := _create_civilian(Vector2(150, 100))
	# Register as pending feeder
	ai.register_pending_feeder(feeder)
	# Should NOT aggro against the feeder
	var target: Node2D = ai._scan_for_aggro_target()
	assert_object(target).is_null()
	# Unregister and try again — should now aggro
	ai.unregister_pending_feeder(feeder)
	target = ai._scan_for_aggro_target()
	assert_object(target).is_same(feeder)
