extends GdUnitTestSuite
## Tests for villager feeding task — assign_feed_target, tick, cancel.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const WolfAIScript := preload("res://scripts/fauna/wolf_ai.gd")

var _wolf_cfg: Dictionary = {
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
	unit.unit_color = Color(0.5, 0.5, 0.5)
	unit.position = pos
	unit.hp = 18
	unit.max_hp = 18
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	var ai := Node.new()
	ai.name = "WolfAI"
	ai.set_script(WolfAIScript)
	unit.add_child(ai)
	ai._cfg = _wolf_cfg
	ai.spawn_origin = pos
	ai._scene_root = self
	return unit


func _setup_food(amount: int) -> void:
	ResourceManager.init_player(0, {})
	ResourceManager.add_resource(0, ResourceManager.ResourceType.FOOD, amount)


# -- assign_feed_target spends food --


func test_assign_feed_target_spends_food() -> void:
	_setup_food(100)
	var villager := _create_villager()
	var wolf := _create_wolf(Vector2(50, 0))
	villager.assign_feed_target(wolf)
	assert_object(villager._feed_target).is_same(wolf)
	# Should have spent 25 food (default cost)
	var remaining: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	assert_int(remaining).is_equal(75)


# -- Cannot feed with insufficient food --


func test_cannot_feed_when_food_insufficient() -> void:
	_setup_food(10)
	var villager := _create_villager()
	var wolf := _create_wolf(Vector2(50, 0))
	villager.assign_feed_target(wolf)
	# Should not have assigned target
	assert_object(villager._feed_target).is_null()
	# Food should be unchanged
	var remaining: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	assert_int(remaining).is_equal(10)


# -- Feed completes after duration --


func test_feed_completes_after_duration() -> void:
	_setup_food(100)
	var villager := _create_villager(Vector2.ZERO)
	var wolf := _create_wolf(Vector2(50, 0))  # Within feed reach (128px)
	villager.assign_feed_target(wolf)
	# Simulate being in range
	villager._moving = false
	# Tick enough for full feed duration
	for i in 60:
		villager._tick_feed(0.1)
	# Feed target should be cleared after completion
	assert_object(villager._feed_target).is_null()
	assert_bool(villager._is_feeding).is_false()


# -- Feed cancelled on death --


func test_feed_cancelled_on_villager_death() -> void:
	_setup_food(100)
	var villager := _create_villager(Vector2.ZERO)
	var wolf := _create_wolf(Vector2(50, 0))
	villager.assign_feed_target(wolf)
	villager._cancel_feed()
	assert_object(villager._feed_target).is_null()
	assert_bool(villager._is_feeding).is_false()


# -- Feed cancels active gather --


func test_feed_cancels_active_gather() -> void:
	_setup_food(100)
	var villager := _create_villager()
	# Simulate an active gather state
	villager._gather_state = UnitScript.GatherState.GATHERING
	villager._gather_type = "food"
	var wolf := _create_wolf(Vector2(50, 0))
	villager.assign_feed_target(wolf)
	# Gather should be cancelled
	assert_int(villager._gather_state).is_equal(UnitScript.GatherState.NONE)
	assert_object(villager._feed_target).is_same(wolf)


# -- is_idle false during feed --


func test_is_idle_false_during_feed() -> void:
	_setup_food(100)
	var villager := _create_villager()
	var wolf := _create_wolf(Vector2(50, 0))
	villager.assign_feed_target(wolf)
	villager._moving = false
	assert_bool(villager.is_idle()).is_false()
