extends GdUnitTestSuite
## Tests for dog_ai.gd — dog companion AI state machine.

const DogAIScript := preload("res://scripts/fauna/dog_ai.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

var _cfg: Dictionary = {
	"alert_radius_tiles": 10,
	"alert_speed_buff": 0.10,
	"alert_buff_duration": 5.0,
	"alert_buff_radius_tiles": 8,
	"alert_cooldown": 15.0,
	"hunt_assist_radius_tiles": 8,
	"hunt_gather_bonus": 0.25,
	"hunt_follow_distance_tiles": 3,
	"town_patrol_radius_tiles": 12,
	"town_patrol_wander_radius_tiles": 8,
	"town_patrol_idle_min": 2.0,
	"town_patrol_idle_max": 3.0,
	"los_bonus": 2,
	"los_bonus_max_stacks": 3,
	"follow_distance_tiles": 3,
	"flee_speed_pixels": 192.0,
	"patrol_speed_pixels": 96.0,
	"scan_interval": 0.5,
}


func _create_dog(pos: Vector2 = Vector2.ZERO, owner: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "dog"
	unit.owner_id = owner
	unit.entity_category = "dog"
	unit.unit_color = Color(0.6, 0.4, 0.2)
	unit.position = pos
	unit.hp = 25
	unit.max_hp = 25
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	var ai := Node.new()
	ai.name = "DogAI"
	ai.set_script(DogAIScript)
	unit.add_child(ai)
	ai._cfg = _cfg
	ai._scene_root = self
	return unit


func _get_ai(unit: Node2D) -> Node:
	return unit.get_node("DogAI")


func _create_tc(pos: Vector2 = Vector2.ZERO, owner: int = 0) -> Node2D:
	var building := Node2D.new()
	building.set_script(BuildingScript)
	building.building_name = "town_center"
	building.owner_id = owner
	building.entity_category = "own_building"
	building.hp = 2400
	building.max_hp = 2400
	building.position = pos
	add_child(building)
	auto_free(building)
	return building


func _create_building(pos: Vector2 = Vector2.ZERO, owner: int = 0, bname: String = "house") -> Node2D:
	var building := Node2D.new()
	building.set_script(BuildingScript)
	building.building_name = bname
	building.owner_id = owner
	building.entity_category = "own_building"
	building.hp = 800
	building.max_hp = 800
	building.position = pos
	add_child(building)
	auto_free(building)
	return building


func _create_villager(pos: Vector2 = Vector2.ZERO, owner: int = 0) -> Node2D:
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


func _create_military(pos: Vector2 = Vector2.ZERO, owner: int = 1) -> Node2D:
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


func test_starts_in_idle_state() -> void:
	var dog := _create_dog()
	var ai := _get_ai(dog)
	assert_int(ai._state).is_equal(DogAIScript.DogState.IDLE)


func test_stance_is_stand_ground() -> void:
	var dog := _create_dog()
	assert_int(dog._stance).is_equal(UnitScript.Stance.STAND_GROUND)


# -- Town Patrol tests --


func test_enters_patrol_near_tc() -> void:
	var tc := _create_tc(Vector2(100, 100))
	assert_object(tc).is_not_null()
	var dog := _create_dog(Vector2(150, 100))
	var ai := _get_ai(dog)
	ai._try_enter_patrol()
	assert_int(ai._state).is_equal(DogAIScript.DogState.TOWN_PATROL)


func test_stays_idle_without_tc() -> void:
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai._try_enter_patrol()
	assert_int(ai._state).is_equal(DogAIScript.DogState.IDLE)


func test_patrol_wanders_to_buildings() -> void:
	var tc := _create_tc(Vector2(100, 100))
	assert_object(tc).is_not_null()
	var house := _create_building(Vector2(200, 100))
	assert_object(house).is_not_null()
	var dog := _create_dog(Vector2(150, 100))
	var ai := _get_ai(dog)
	ai._enter_town_patrol()
	ai._patrol_idle_timer = 0.0
	ai._tick_town_patrol(0.1)
	# After idle timer expires, should pick a patrol target
	assert_bool(ai._is_moving).is_true()


func test_los_bonus_applied_to_nearby_building() -> void:
	var tc := _create_tc(Vector2(100, 100))
	assert_object(tc).is_not_null()
	var dog := _create_dog(Vector2(150, 100))
	var ai := _get_ai(dog)
	ai._enter_town_patrol()
	ai._update_town_los_bonus()
	assert_int(tc._dog_los_bonus).is_greater(0)


func test_los_bonus_removed_on_clear() -> void:
	var tc := _create_tc(Vector2(100, 100))
	assert_object(tc).is_not_null()
	var dog := _create_dog(Vector2(150, 100))
	var ai := _get_ai(dog)
	ai._update_town_los_bonus()
	assert_int(tc._dog_los_bonus).is_greater(0)
	ai._clear_los_bonus()
	assert_int(tc._dog_los_bonus).is_equal(0)


func test_los_bonus_stacking_cap() -> void:
	var tc := _create_tc(Vector2(100, 100))
	assert_object(tc).is_not_null()
	var los_bonus: int = int(_cfg["los_bonus"])
	var max_stacks: int = int(_cfg["los_bonus_max_stacks"])
	# Simulate applying bonus many times
	tc.set_dog_los_bonus(max_stacks * los_bonus)
	var dog := _create_dog(Vector2(150, 100))
	var ai := _get_ai(dog)
	# The update should cap at max_stacks * los_bonus
	ai._update_town_los_bonus()
	assert_int(tc._dog_los_bonus).is_less_equal(max_stacks * los_bonus)


# -- Hunt Assist tests --


func test_enters_hunt_assist_near_hunting_villager() -> void:
	var tc := _create_tc(Vector2(100, 100))
	assert_object(tc).is_not_null()
	var villager := _create_villager(Vector2(200, 100))
	# Simulate villager gathering food
	villager._gather_state = UnitScript.GatherState.GATHERING
	villager._gather_type = "food"
	var dog := _create_dog(Vector2(250, 100))
	var ai := _get_ai(dog)
	var hunter: Node2D = ai._find_hunting_villager()
	assert_object(hunter).is_same(villager)


func test_gather_bonus_applied_during_hunt_assist() -> void:
	var villager := _create_villager(Vector2(200, 100))
	villager._gather_state = UnitScript.GatherState.GATHERING
	villager._gather_type = "food"
	var dog := _create_dog(Vector2(250, 100))
	var ai := _get_ai(dog)
	ai._enter_hunt_assist(villager)
	var expected: float = 1.0 + float(_cfg["hunt_gather_bonus"])
	assert_float(villager._gather_rate_multiplier).is_equal_approx(expected, 0.001)


func test_gather_bonus_removed_when_villager_stops() -> void:
	var villager := _create_villager(Vector2(200, 100))
	villager._gather_state = UnitScript.GatherState.GATHERING
	villager._gather_type = "food"
	var dog := _create_dog(Vector2(250, 100))
	var ai := _get_ai(dog)
	ai._enter_hunt_assist(villager)
	# Villager stops gathering
	villager._gather_state = UnitScript.GatherState.NONE
	ai._tick_hunt_assist(0.1)
	assert_float(villager._gather_rate_multiplier).is_equal_approx(1.0, 0.001)


func test_hunt_assist_follows_villager() -> void:
	var villager := _create_villager(Vector2(500, 100))
	villager._gather_state = UnitScript.GatherState.GATHERING
	villager._gather_type = "food"
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai._enter_hunt_assist(villager)
	ai._tick_hunt_assist(0.1)
	# Dog should be moving toward villager
	assert_bool(ai._is_moving).is_true()


func test_ignores_non_food_gatherer() -> void:
	var villager := _create_villager(Vector2(200, 100))
	villager._gather_state = UnitScript.GatherState.GATHERING
	villager._gather_type = "wood"
	var dog := _create_dog(Vector2(250, 100))
	var ai := _get_ai(dog)
	var hunter: Node2D = ai._find_hunting_villager()
	assert_object(hunter).is_null()


# -- Danger Alert tests --


func test_alert_triggers_on_enemy() -> void:
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	# Place enemy military within alert radius (10 tiles = 640 px)
	var enemy := _create_military(Vector2(200, 100), 1)
	assert_object(enemy).is_not_null()
	ai._scan_timer = 1.0  # Past scan interval
	ai._tick_danger_alert(0.0)
	# Should have transitioned to flee
	assert_int(ai._state).is_equal(DogAIScript.DogState.FLEE)


func test_alert_cooldown_prevents_spam() -> void:
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	var enemy := _create_military(Vector2(200, 100), 1)
	assert_object(enemy).is_not_null()
	ai._scan_timer = 1.0
	ai._tick_danger_alert(0.0)
	var first_cooldown: float = ai._alert_cooldown_timer
	assert_float(first_cooldown).is_greater(0.0)
	# Reset state for second check
	ai._state = DogAIScript.DogState.IDLE
	ai._scan_timer = 1.0
	# Cooldown still active — should not trigger
	ai._tick_danger_alert(0.1)
	assert_int(ai._state).is_equal(DogAIScript.DogState.IDLE)


func test_alert_buff_removed_after_duration() -> void:
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai._alert_buff_active = true
	ai._alert_buff_timer = 0.5
	ai._tick_alert_buff_decay(0.6)
	assert_bool(ai._alert_buff_active).is_false()


func test_alert_transitions_to_flee() -> void:
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai._enter_town_patrol()
	var enemy := _create_military(Vector2(200, 100), 1)
	assert_object(enemy).is_not_null()
	ai._scan_timer = 1.0
	ai._tick_danger_alert(0.0)
	assert_int(ai._state).is_equal(DogAIScript.DogState.FLEE)


func test_no_alert_without_enemy() -> void:
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai._scan_timer = 1.0
	ai._tick_danger_alert(0.0)
	# Should still be in IDLE (no transition)
	assert_int(ai._state).is_equal(DogAIScript.DogState.IDLE)


func test_cleanup_on_dog_death() -> void:
	var tc := _create_tc(Vector2(100, 100))
	assert_object(tc).is_not_null()
	var villager := _create_villager(Vector2(200, 100))
	villager._gather_state = UnitScript.GatherState.GATHERING
	villager._gather_type = "food"
	var dog := _create_dog(Vector2(150, 100))
	var ai := _get_ai(dog)
	ai._enter_hunt_assist(villager)
	ai._update_town_los_bonus()
	# Dog dies
	ai._on_dog_died(dog)
	assert_float(villager._gather_rate_multiplier).is_equal_approx(1.0, 0.001)
	assert_int(tc._dog_los_bonus).is_equal(0)


# -- Flee tests --


func test_flees_toward_tc() -> void:
	var tc := _create_tc(Vector2(500, 500))
	assert_object(tc).is_not_null()
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai._enter_flee()
	assert_int(ai._state).is_equal(DogAIScript.DogState.FLEE)
	# Flee destination should be near TC
	assert_float(ai._flee_destination.distance_to(tc.global_position)).is_less(1.0)


func test_flees_toward_military_if_no_tc() -> void:
	var friendly := _create_military(Vector2(500, 500), 0)
	assert_object(friendly).is_not_null()
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai._enter_flee()
	# Flee destination should be near friendly military
	assert_float(ai._flee_destination.distance_to(friendly.global_position)).is_less(1.0)


func test_returns_to_patrol_when_safe() -> void:
	var tc := _create_tc(Vector2(100, 100))
	assert_object(tc).is_not_null()
	var dog := _create_dog(Vector2(150, 100))
	var ai := _get_ai(dog)
	ai._state = DogAIScript.DogState.FLEE
	ai._is_moving = false  # Arrived at destination
	ai._tick_flee(0.1)
	# No enemies around — should transition back to patrol
	assert_int(ai._state).is_equal(DogAIScript.DogState.TOWN_PATROL)


# -- Follow tests --


func test_follows_commanded_unit() -> void:
	var target := _create_villager(Vector2(500, 500))
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai.command_follow(target)
	assert_int(ai._state).is_equal(DogAIScript.DogState.FOLLOW)
	assert_object(ai._follow_target).is_same(target)


func test_follow_canceled_on_target_death() -> void:
	var tc := _create_tc(Vector2(100, 100))
	assert_object(tc).is_not_null()
	var target := _create_villager(Vector2(500, 500))
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai.command_follow(target)
	target.hp = 0
	ai._tick_follow(0.1)
	# Should return to patrol/idle
	assert_int(ai._state).is_not_equal(DogAIScript.DogState.FOLLOW)


func test_follow_overridable() -> void:
	var target1 := _create_villager(Vector2(500, 500))
	var target2 := _create_villager(Vector2(300, 300))
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai.command_follow(target1)
	assert_object(ai._follow_target).is_same(target1)
	ai.command_follow(target2)
	assert_object(ai._follow_target).is_same(target2)


# -- Garrison tests --


func test_los_bonus_persists_while_near_building() -> void:
	var tc := _create_tc(Vector2(100, 100))
	var dog := _create_dog(Vector2(150, 100))
	var ai := _get_ai(dog)
	ai._update_town_los_bonus()
	assert_int(tc._dog_los_bonus).is_greater(0)
	# Still near — bonus should remain
	ai._update_town_los_bonus()
	assert_int(tc._dog_los_bonus).is_greater(0)


func test_los_bonus_removed_when_far_away() -> void:
	var tc := _create_tc(Vector2(100, 100))
	var dog := _create_dog(Vector2(150, 100))
	var ai := _get_ai(dog)
	ai._update_town_los_bonus()
	assert_int(tc._dog_los_bonus).is_greater(0)
	# Move dog far away
	dog.position = Vector2(5000, 5000)
	ai._update_town_los_bonus()
	assert_int(tc._dog_los_bonus).is_equal(0)


# -- Save / Load tests --


func test_save_load_round_trip() -> void:
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai._state = DogAIScript.DogState.TOWN_PATROL
	ai._alert_cooldown_timer = 5.0
	ai._patrol_idle_timer = 1.5
	ai._is_moving = true
	ai._move_target = Vector2(300, 400)
	var saved: Dictionary = ai.save_state()
	# Create fresh dog and load state
	var dog2 := _create_dog(Vector2(0, 0))
	var ai2 := _get_ai(dog2)
	ai2.load_state(saved)
	assert_int(ai2._state).is_equal(DogAIScript.DogState.TOWN_PATROL)
	assert_float(ai2._alert_cooldown_timer).is_equal_approx(5.0, 0.001)
	assert_float(ai2._patrol_idle_timer).is_equal_approx(1.5, 0.001)
	assert_bool(ai2._is_moving).is_true()
	assert_float(ai2._move_target.x).is_equal_approx(300.0, 0.001)
	assert_float(ai2._move_target.y).is_equal_approx(400.0, 0.001)


func test_save_load_preserves_target_names() -> void:
	var target := _create_villager(Vector2(500, 500))
	target.name = "TestFollowTarget"
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai.command_follow(target)
	var saved: Dictionary = ai.save_state()
	assert_str(str(saved.get("follow_target_name", ""))).is_equal("TestFollowTarget")


func test_resolve_targets_after_load() -> void:
	var target := _create_villager(Vector2(500, 500))
	target.name = "FollowUnit"
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	ai._pending_follow_target_name = "FollowUnit"
	ai.resolve_targets(self)
	assert_object(ai._follow_target).is_same(target)


func test_save_load_timer_preservation() -> void:
	var dog := _create_dog()
	var ai := _get_ai(dog)
	ai._alert_buff_active = true
	ai._alert_buff_timer = 3.5
	ai._scan_timer = 0.3
	var saved: Dictionary = ai.save_state()
	var dog2 := _create_dog()
	var ai2 := _get_ai(dog2)
	ai2.load_state(saved)
	assert_bool(ai2._alert_buff_active).is_true()
	assert_float(ai2._alert_buff_timer).is_equal_approx(3.5, 0.001)
	assert_float(ai2._scan_timer).is_equal_approx(0.3, 0.001)


# -- No combat test --


func test_dog_never_attacks() -> void:
	var dog := _create_dog(Vector2(100, 100))
	var ai := _get_ai(dog)
	# Place enemy right next to dog
	var enemy := _create_military(Vector2(120, 100), 1)
	assert_object(enemy).is_not_null()
	# Tick process — combat should stay suppressed
	ai._state = DogAIScript.DogState.IDLE
	assert_int(dog._combat_state).is_equal(UnitScript.CombatState.NONE)
	assert_int(dog._stance).is_equal(UnitScript.Stance.STAND_GROUND)
