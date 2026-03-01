extends GdUnitTestSuite
## Tests for HealFeedComponent — wolf feeding state machine, heal regen, save/load.

const HealFeedScript := preload("res://scripts/prototype/heal_feed_component.gd")
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


func _create_unit(pos: Vector2 = Vector2.ZERO) -> Node2D:
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


func _get_comp(unit: Node2D) -> RefCounted:
	return unit._heal_feed


# -- Feed state machine transitions --


func test_idle_to_feeding_transition() -> void:
	_setup_food(100)
	var villager := _create_unit(Vector2.ZERO)
	var wolf := _create_wolf(Vector2(50, 0))  # Within feed_reach (128px)
	var comp: RefCounted = _get_comp(villager)

	# Before assignment — idle state
	assert_object(comp.feed_target).is_null()
	assert_bool(comp.is_feeding).is_false()
	assert_float(comp.feed_timer).is_equal(0.0)

	# Assign target — moves to "approaching" state (target set, not yet feeding)
	comp.assign_feed_target(wolf)
	assert_object(comp.feed_target).is_same(wolf)
	assert_bool(comp.is_feeding).is_false()
	assert_float(comp.feed_timer).is_equal(0.0)


func test_feeding_starts_when_in_range() -> void:
	_setup_food(100)
	var villager := _create_unit(Vector2.ZERO)
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)
	comp.assign_feed_target(wolf)

	# Tick once — within range, should start feeding
	comp._tick_feed(0.1)
	assert_bool(comp.is_feeding).is_true()
	assert_float(comp.feed_timer).is_equal_approx(0.1, 0.01)


func test_feeding_completes_after_duration() -> void:
	_setup_food(100)
	var villager := _create_unit(Vector2.ZERO)
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)
	comp.assign_feed_target(wolf)

	# Tick past full duration (5.0s default)
	for i in 60:
		comp._tick_feed(0.1)

	# Should have completed and cleared state
	assert_object(comp.feed_target).is_null()
	assert_bool(comp.is_feeding).is_false()
	assert_float(comp.feed_timer).is_equal(0.0)


func test_feeding_not_started_when_out_of_range() -> void:
	_setup_food(100)
	var villager := _create_unit(Vector2.ZERO)
	var wolf := _create_wolf(Vector2(500, 0))  # Far beyond feed_reach
	var comp: RefCounted = _get_comp(villager)
	comp.assign_feed_target(wolf)

	# Tick — should not start feeding (too far)
	comp._tick_feed(0.1)
	assert_bool(comp.is_feeding).is_false()
	assert_float(comp.feed_timer).is_equal(0.0)


# -- Feed target assignment and clearing --


func test_assign_feed_target_spends_food() -> void:
	_setup_food(100)
	var villager := _create_unit()
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)

	comp.assign_feed_target(wolf)
	assert_object(comp.feed_target).is_same(wolf)
	var remaining: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	assert_int(remaining).is_equal(75)


func test_assign_feed_target_fails_when_food_insufficient() -> void:
	_setup_food(10)
	var villager := _create_unit()
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)

	comp.assign_feed_target(wolf)
	assert_object(comp.feed_target).is_null()
	var remaining: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	assert_int(remaining).is_equal(10)


func test_assign_feed_registers_pending_feeder() -> void:
	_setup_food(100)
	var villager := _create_unit()
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)
	var wolf_ai: Node = wolf.get_node("WolfAI")

	comp.assign_feed_target(wolf)
	assert_object(wolf_ai._pending_feeder).is_same(villager)


# -- Cancel --


func test_cancel_before_feeding_unregisters_pending() -> void:
	_setup_food(100)
	var villager := _create_unit()
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)
	var wolf_ai: Node = wolf.get_node("WolfAI")

	comp.assign_feed_target(wolf)
	assert_object(wolf_ai._pending_feeder).is_same(villager)

	comp.cancel()
	assert_object(comp.feed_target).is_null()
	assert_bool(comp.is_feeding).is_false()
	assert_object(wolf_ai._pending_feeder).is_null()


func test_cancel_during_feeding_cancels_wolf_ai() -> void:
	_setup_food(100)
	var villager := _create_unit(Vector2.ZERO)
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)
	var wolf_ai: Node = wolf.get_node("WolfAI")

	comp.assign_feed_target(wolf)
	# Tick into feeding state
	comp._tick_feed(0.1)
	assert_bool(comp.is_feeding).is_true()

	comp.cancel()
	assert_object(comp.feed_target).is_null()
	assert_bool(comp.is_feeding).is_false()
	# Wolf should have feed lockout timer set
	assert_float(wolf_ai._feed_lockout_timer).is_greater(0.0)


func test_cancel_with_no_target_is_safe() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)
	# Should not error
	comp.cancel()
	assert_object(comp.feed_target).is_null()


# -- Target freed before feed completes --


func test_target_freed_clears_state() -> void:
	_setup_food(100)
	var villager := _create_unit(Vector2.ZERO)
	villager.set_process(false)
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)

	comp.assign_feed_target(wolf)
	comp._tick_feed(0.1)
	assert_bool(comp.is_feeding).is_true()

	# Free the wolf mid-feed (immediate free so reference becomes invalid)
	remove_child(wolf)
	wolf.free()

	# Next tick should detect invalid target and clear
	comp._tick_feed(0.1)
	assert_object(comp.feed_target).is_null()
	assert_bool(comp.is_feeding).is_false()


func test_wolf_without_ai_clears_state() -> void:
	_setup_food(100)
	var villager := _create_unit(Vector2.ZERO)
	villager.set_process(false)
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)

	comp.assign_feed_target(wolf)
	# Remove WolfAI node before tick
	var ai: Node = wolf.get_node("WolfAI")
	wolf.remove_child(ai)
	ai.free()

	comp._tick_feed(0.1)
	assert_object(comp.feed_target).is_null()
	assert_bool(comp.is_feeding).is_false()


# -- Save/load round-trip --


func test_save_state_captures_feed_progress() -> void:
	_setup_food(100)
	var villager := _create_unit(Vector2.ZERO)
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)

	comp.assign_feed_target(wolf)
	comp._tick_feed(2.5)
	assert_bool(comp.is_feeding).is_true()

	var state: Dictionary = comp.save_state()
	assert_bool(state["is_feeding"]).is_true()
	assert_float(state["feed_timer"]).is_equal_approx(2.5, 0.01)
	assert_str(state["feed_target_name"]).is_equal(str(wolf.name))


func test_save_state_without_target() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)

	var state: Dictionary = comp.save_state()
	assert_bool(state["is_feeding"]).is_false()
	assert_float(state["feed_timer"]).is_equal(0.0)
	assert_bool(state.has("feed_target_name")).is_false()


func test_load_state_restores_feed_progress() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)

	var data := {
		"is_feeding": true,
		"feed_timer": 3.0,
		"feed_target_name": "SomeWolf",
		"heal_accumulator": 0.5,
	}
	comp.load_state(data)

	assert_bool(comp.is_feeding).is_true()
	assert_float(comp.feed_timer).is_equal(3.0)
	assert_float(comp.heal_accumulator).is_equal(0.5)
	assert_str(comp.pending_feed_target_name).is_equal("SomeWolf")


func test_load_state_with_empty_data() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)

	comp.load_state({})
	assert_bool(comp.is_feeding).is_false()
	assert_float(comp.feed_timer).is_equal(0.0)
	assert_float(comp.heal_accumulator).is_equal(0.0)
	assert_str(comp.pending_feed_target_name).is_equal("")


# -- resolve_target --


func test_resolve_target_links_pending_name() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)

	# Create a wolf in the scene tree
	var wolf := _create_wolf(Vector2(50, 0))

	# Simulate post-load: set pending name to the wolf's actual name
	comp.pending_feed_target_name = str(wolf.name)
	comp.resolve_target(self)

	assert_object(comp.feed_target).is_same(wolf)
	assert_str(comp.pending_feed_target_name).is_equal("")


func test_resolve_target_clears_invalid_name() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)

	comp.pending_feed_target_name = "NonExistentNode"
	comp.resolve_target(self)

	# Target should remain null, pending name cleared
	assert_object(comp.feed_target).is_null()
	assert_str(comp.pending_feed_target_name).is_equal("")


func test_resolve_target_skips_empty_name() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)

	comp.resolve_target(self)
	assert_object(comp.feed_target).is_null()
	assert_str(comp.pending_feed_target_name).is_equal("")


# -- Save/load round-trip integration --


func test_save_load_roundtrip_with_pending_target() -> void:
	_setup_food(100)
	var villager := _create_unit(Vector2.ZERO)
	var wolf := _create_wolf(Vector2(50, 0))
	var comp: RefCounted = _get_comp(villager)

	# Start feeding and progress
	comp.assign_feed_target(wolf)
	comp._tick_feed(2.0)
	assert_bool(comp.is_feeding).is_true()

	# Save
	var state: Dictionary = comp.save_state()

	# Create fresh unit and component, load state
	var villager2 := _create_unit(Vector2.ZERO)
	var comp2: RefCounted = _get_comp(villager2)
	comp2.load_state(state)

	# Verify pending state
	assert_bool(comp2.is_feeding).is_true()
	assert_float(comp2.feed_timer).is_equal_approx(2.0, 0.01)
	assert_str(comp2.pending_feed_target_name).is_equal(str(wolf.name))

	# Resolve target
	comp2.resolve_target(self)
	assert_object(comp2.feed_target).is_same(wolf)
	assert_str(comp2.pending_feed_target_name).is_equal("")


# -- Heal behavior --


func test_heal_accumulates_over_time() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)
	villager.hp = 20  # Below max_hp of 25

	# Set up stats with self_heal_rate
	villager.stats._base_stats["self_heal_rate"] = 2.0

	# Tick 0.5s at rate 2.0 = accumulate 1.0 → heal 1 HP
	comp._tick_heal(0.5)
	assert_int(villager.hp).is_equal(21)
	assert_float(comp.heal_accumulator).is_equal_approx(0.0, 0.01)


func test_heal_does_not_exceed_max_hp() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)
	villager.hp = 24  # 1 below max
	villager.stats._base_stats["self_heal_rate"] = 10.0

	# Tick 1.0s at rate 10.0 = would heal 10, but capped at max_hp
	comp._tick_heal(1.0)
	assert_int(villager.hp).is_equal(25)


func test_heal_skips_at_full_hp() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)
	villager.hp = 25  # At max
	villager.stats._base_stats["self_heal_rate"] = 2.0

	comp._tick_heal(1.0)
	assert_int(villager.hp).is_equal(25)
	assert_float(comp.heal_accumulator).is_equal(0.0)


func test_heal_skips_at_zero_hp() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)
	villager.hp = 0
	villager.stats._base_stats["self_heal_rate"] = 2.0

	comp._tick_heal(1.0)
	assert_int(villager.hp).is_equal(0)


func test_heal_skips_without_self_heal_rate() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)
	villager.hp = 20

	# No self_heal_rate in stats
	comp._tick_heal(1.0)
	assert_int(villager.hp).is_equal(20)
	assert_float(comp.heal_accumulator).is_equal(0.0)


func test_heal_skips_during_combat() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)
	villager.hp = 20
	villager.stats._base_stats["self_heal_rate"] = 2.0

	# Simulate combat state != NONE (0)
	if villager._combatant != null:
		villager._combatant.combat_state = 1  # Not NONE

	comp._tick_heal(1.0)
	# If combatant exists and is in combat, HP should not change
	if villager._combatant != null:
		assert_int(villager.hp).is_equal(20)


func test_heal_accumulator_preserved_across_ticks() -> void:
	var villager := _create_unit()
	var comp: RefCounted = _get_comp(villager)
	villager.hp = 20
	villager.stats._base_stats["self_heal_rate"] = 1.0

	# Tick 0.3s — accumulate 0.3, no heal yet
	comp._tick_heal(0.3)
	assert_int(villager.hp).is_equal(20)
	assert_float(comp.heal_accumulator).is_equal_approx(0.3, 0.01)

	# Tick another 0.3s — accumulate 0.6, still no heal
	comp._tick_heal(0.3)
	assert_int(villager.hp).is_equal(20)
	assert_float(comp.heal_accumulator).is_equal_approx(0.6, 0.01)

	# Tick another 0.5s — accumulate 1.1, heal 1 HP, remainder 0.1
	comp._tick_heal(0.5)
	assert_int(villager.hp).is_equal(21)
	assert_float(comp.heal_accumulator).is_equal_approx(0.1, 0.01)
