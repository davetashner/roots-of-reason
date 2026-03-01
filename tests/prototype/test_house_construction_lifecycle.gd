extends GdUnitTestSuite
## Integration test: full house construction lifecycle.
## Covers: placement → ghost alignment → foundation → partial build → complete,
## selection of buildings under construction, multi-villager build acceleration,
## and frame progression through building sequence spritesheet.

const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const PlacerScript := preload("res://scripts/prototype/building_placer.gd")
const MapScript := preload("res://scripts/prototype/prototype_map.gd")
const PathfindingScript := preload("res://scripts/prototype/pathfinding_grid.gd")
const TargetDetectorScript := preload("res://scripts/prototype/target_detector.gd")
const InputScript := preload("res://scripts/prototype/prototype_input.gd")
const FlowScript := preload("res://scripts/prototype/game_flow_controller.gd")
const EntityRegistryScript := preload("res://scripts/prototype/entity_registry.gd")

var _original_age: int = 0


## Lightweight stand-in for prototype_main — exposes the typed vars that
## game_flow_controller reads from _root without loading the full scene.
class MockRoot:
	extends Node2D
	var _input_handler: Node = null
	var _entity_registry: RefCounted = null
	var _population_manager: Node = null
	var _game_stats_tracker: Node = null
	var _tech_manager: Node = null


func before() -> void:
	_original_age = GameManager.current_age


func after() -> void:
	GameManager.current_age = _original_age


# -- Helpers --


func _build_grass_grid(size: int) -> Dictionary:
	var grid: Dictionary = {}
	for x in size:
		for y in size:
			grid[Vector2i(x, y)] = "grass"
	return grid


func _create_scene() -> Dictionary:
	## Build a minimal game scene with placer, input handler, flow controller,
	## and entity registry — enough to test the full placement-to-completion path.
	var scene := MockRoot.new()
	scene.name = "TestScene"
	add_child(scene)
	auto_free(scene)
	# Map
	var map := Node2D.new()
	map.name = "Map"
	map.set_script(MapScript)
	map._tile_grid = _build_grass_grid(20)
	scene.add_child(map)
	# Pathfinder
	var pf := Node.new()
	pf.name = "PathfindingGrid"
	pf.set_script(PathfindingScript)
	scene.add_child(pf)
	pf.build(20, map._tile_grid, {"grass": 1.0, "forest": 2.0, "desert": 1.5, "water": -1})
	# Target detector
	var td := Node.new()
	td.name = "TargetDetector"
	td.set_script(TargetDetectorScript)
	scene.add_child(td)
	# Camera
	var cam := Camera2D.new()
	cam.name = "Camera"
	scene.add_child(cam)
	# Input handler
	var input_handler := Node.new()
	input_handler.name = "InputHandler"
	input_handler.set_script(InputScript)
	scene.add_child(input_handler)
	# Entity registry
	var registry := EntityRegistryScript.new()
	# Placer
	var placer := Node.new()
	placer.name = "BuildingPlacer"
	placer.set_script(PlacerScript)
	scene.add_child(placer)
	placer.setup(cam, pf, map, td)
	# Flow controller
	var flow := FlowScript.new()
	scene._input_handler = input_handler
	scene._entity_registry = registry
	flow.setup(scene, null)
	# Init player resources
	var starting: Dictionary = {
		ResourceManager.ResourceType.WOOD: 1000,
		ResourceManager.ResourceType.STONE: 500,
		ResourceManager.ResourceType.FOOD: 200,
		ResourceManager.ResourceType.GOLD: 200,
	}
	ResourceManager.init_player(0, starting)
	return {
		"scene": scene,
		"placer": placer,
		"input_handler": input_handler,
		"registry": registry,
		"flow": flow,
		"pathfinder": pf,
		"target_detector": td,
	}


func _create_unit(scene: Node2D, pos: Vector2 = Vector2.ZERO) -> Node2D:
	var u := Node2D.new()
	u.set_script(UnitScript)
	u.unit_type = "villager"
	u.owner_id = 0
	u.position = pos
	u._build_speed = 1.0
	u._build_reach = 80.0
	scene.add_child(u)
	auto_free(u)
	return u


func _place_house(ctx: Dictionary, grid_pos: Vector2i) -> Node2D:
	## Start and confirm house placement at the given grid position.
	var placer: Node = ctx["placer"]
	placer.start_placement("house", 0)
	placer._current_grid_pos = grid_pos
	placer._is_valid = true
	placer._confirm_placement()
	# Find the placed building node
	for entry: Dictionary in placer._placed_buildings:
		var node: Node2D = entry.get("node")
		if is_instance_valid(node) and node.building_name == "house":
			return node
	return null


# ---------------------------------------------------------------------------
# Placement & Ghost Alignment
# ---------------------------------------------------------------------------


func test_placed_house_position_matches_grid() -> void:
	var ctx := _create_scene()
	var grid_pos := Vector2i(5, 5)
	var house := _place_house(ctx, grid_pos)
	assert_that(house).is_not_null()
	var expected_pos := IsoUtils.grid_to_screen(Vector2(grid_pos))
	assert_vector(house.position).is_equal(expected_pos)


func test_placed_house_grid_pos_stored() -> void:
	var ctx := _create_scene()
	var grid_pos := Vector2i(7, 3)
	var house := _place_house(ctx, grid_pos)
	assert_object(house.grid_pos).is_equal(grid_pos)


func test_placed_house_footprint_is_2x2() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	assert_object(house.footprint).is_equal(Vector2i(2, 2))


func test_placed_house_marks_footprint_cells_solid() -> void:
	var ctx := _create_scene()
	var pf: Node = ctx["pathfinder"]
	var grid_pos := Vector2i(5, 5)
	_place_house(ctx, grid_pos)
	assert_bool(pf.is_cell_solid(Vector2i(5, 5))).is_true()
	assert_bool(pf.is_cell_solid(Vector2i(6, 5))).is_true()
	assert_bool(pf.is_cell_solid(Vector2i(5, 6))).is_true()
	assert_bool(pf.is_cell_solid(Vector2i(6, 6))).is_true()


# ---------------------------------------------------------------------------
# Initial Construction State
# ---------------------------------------------------------------------------


func test_placed_house_starts_under_construction() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	assert_bool(house.under_construction).is_true()
	assert_float(house.build_progress).is_equal_approx(0.0, 0.001)
	assert_int(house.hp).is_equal(0)


func test_placed_house_category_is_construction_site() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	assert_str(house.get_entity_category()).is_equal("construction_site")


func test_placed_house_max_hp_from_data() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	# house.json defines hp: 550
	assert_int(house.max_hp).is_equal(550)


# ---------------------------------------------------------------------------
# Selection (the fix: register_unit on placement)
# ---------------------------------------------------------------------------


func test_placed_house_registered_with_input_handler() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	# Wire through flow controller
	var flow: RefCounted = ctx["flow"]
	flow.on_building_placed(house)
	var input_handler: Node = ctx["input_handler"]
	assert_bool(house in input_handler._units).is_true()


func test_placed_house_can_be_selected() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	var flow: RefCounted = ctx["flow"]
	flow.on_building_placed(house)
	house.select()
	assert_bool(house.selected).is_true()


func test_placed_house_selectable_via_is_point_inside() -> void:
	var ctx := _create_scene()
	var grid_pos := Vector2i(5, 5)
	var house := _place_house(ctx, grid_pos)
	# Point at the building's origin cell center should be inside
	assert_bool(house.is_point_inside(house.global_position)).is_true()


# ---------------------------------------------------------------------------
# Single Villager Construction Progress
# ---------------------------------------------------------------------------


func test_single_villager_advances_progress() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	var u := _create_unit(ctx["scene"], house.position + Vector2(10, 0))
	u._build_target = house
	u._moving = false
	# House build_time = 15s. work = build_speed(1.0) / build_time(15.0) * delta
	# 1 second: 1.0/15.0 = 0.0667
	u._tick_build(1.0)
	assert_float(house.build_progress).is_greater(0.0)
	assert_float(house.build_progress).is_equal_approx(1.0 / 15.0, 0.001)


func test_construction_scales_hp_with_progress() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	house.apply_build_work(0.5)
	assert_int(house.hp).is_equal(int(0.5 * 550))


func test_construction_completes_at_full_progress() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	house.apply_build_work(1.0)
	assert_bool(house.under_construction).is_false()
	assert_int(house.hp).is_equal(550)
	assert_float(house.build_progress).is_equal_approx(1.0, 0.001)


func test_construction_complete_signal_emitted() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	var monitor := monitor_signals(house)
	house.apply_build_work(1.0)
	await assert_signal(monitor).is_emitted("construction_complete", [house])


func test_completed_house_category_is_own_building() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	house.apply_build_work(1.0)
	assert_str(house.get_entity_category()).is_equal("own_building")


# ---------------------------------------------------------------------------
# Building Sequence Frame Progression (foundation → partial → complete)
# ---------------------------------------------------------------------------


func test_frame_index_at_zero_progress() -> void:
	## At 0% progress the building should show frame 0 (foundation).
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	# House has 3 frames (768 / 256 = 3)
	if house._build_seq_frame_count >= 3:
		assert_int(house._get_build_frame_index()).is_equal(0)


func test_frame_index_at_early_progress() -> void:
	## At 20% progress the building should still show frame 0 (foundation).
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	house.build_progress = 0.20
	if house._build_seq_frame_count >= 3:
		assert_int(house._get_build_frame_index()).is_equal(0)


func test_frame_index_at_mid_progress() -> void:
	## At 50% progress the building should show frame 1 (partial/framing).
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	house.build_progress = 0.50
	if house._build_seq_frame_count >= 3:
		assert_int(house._get_build_frame_index()).is_equal(1)


func test_frame_index_at_late_progress() -> void:
	## At 80% progress the building should show frame 2 (roof/complete).
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	house.build_progress = 0.80
	if house._build_seq_frame_count >= 3:
		assert_int(house._get_build_frame_index()).is_equal(2)


func test_frame_index_at_full_progress() -> void:
	## At 100% progress the building should show the last frame.
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	house.build_progress = 1.0
	if house._build_seq_frame_count >= 3:
		assert_int(house._get_build_frame_index()).is_equal(2)


func test_frame_progression_through_full_build() -> void:
	## Incrementally build and verify frames advance: 0 → 1 → 2.
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	if house._build_seq_frame_count < 3:
		return  # Skip if no building sequence spritesheet
	# Foundation phase (0-33%)
	assert_int(house._get_build_frame_index()).is_equal(0)
	house.apply_build_work(0.10)
	assert_int(house._get_build_frame_index()).is_equal(0)
	house.apply_build_work(0.10)
	assert_int(house._get_build_frame_index()).is_equal(0)
	# Partial build phase (33-66%)
	house.apply_build_work(0.15)
	assert_float(house.build_progress).is_equal_approx(0.35, 0.001)
	assert_int(house._get_build_frame_index()).is_equal(1)
	house.apply_build_work(0.20)
	assert_int(house._get_build_frame_index()).is_equal(1)
	# Complete phase (66%+)
	house.apply_build_work(0.15)
	assert_float(house.build_progress).is_equal_approx(0.70, 0.001)
	assert_int(house._get_build_frame_index()).is_equal(2)
	# Finish construction
	house.apply_build_work(0.30)
	assert_bool(house.under_construction).is_false()
	assert_int(house.hp).is_equal(550)


# ---------------------------------------------------------------------------
# Multi-Villager Construction (velocity scales with worker count)
# ---------------------------------------------------------------------------


func test_two_villagers_build_faster_than_one() -> void:
	## Compare build rates directly: 2 villagers on same building contribute 2x work.
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	var u1 := _create_unit(ctx["scene"], house.position + Vector2(10, 0))
	var u2 := _create_unit(ctx["scene"], house.position + Vector2(-10, 0))
	u1._build_target = house
	u1._moving = false
	# One tick from u1 alone
	u1._tick_build(1.0)
	var progress_one: float = house.build_progress
	# Now u2 also ticks — total after this should be progress_one * 2
	u2._build_target = house
	u2._moving = false
	# Reset to measure cleanly: apply exact same delta to both
	house.build_progress = 0.0
	house.hp = 0
	house.under_construction = true
	u1._tick_build(1.0)
	u2._tick_build(1.0)
	# Two villagers should contribute exactly 2x a single villager
	assert_float(house.build_progress).is_equal_approx(progress_one * 2.0, 0.001)


func test_three_villagers_triple_build_speed() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	var u1 := _create_unit(ctx["scene"], house.position + Vector2(10, 0))
	var u2 := _create_unit(ctx["scene"], house.position + Vector2(-10, 0))
	var u3 := _create_unit(ctx["scene"], house.position + Vector2(0, 10))
	u1._build_target = house
	u2._build_target = house
	u3._build_target = house
	u1._moving = false
	u2._moving = false
	u3._moving = false
	# Each contributes 1.0/15.0 per second; 3 villagers = 3/15 = 0.2
	u1._tick_build(1.0)
	u2._tick_build(1.0)
	u3._tick_build(1.0)
	assert_float(house.build_progress).is_equal_approx(3.0 / 15.0, 0.001)


func test_add_villager_to_existing_construction() -> void:
	## A second villager joining mid-construction increases build rate.
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	var u1 := _create_unit(ctx["scene"], house.position + Vector2(10, 0))
	u1._build_target = house
	u1._moving = false
	# Build for 5 seconds with 1 villager
	for i in 5:
		u1._tick_build(1.0)
	var progress_after_solo: float = house.build_progress
	# Expected: 5 * (1.0/15.0) = 0.3333
	assert_float(progress_after_solo).is_equal_approx(5.0 / 15.0, 0.001)
	# Add a second villager
	var u2 := _create_unit(ctx["scene"], house.position + Vector2(-10, 0))
	u2._build_target = house
	u2._moving = false
	# Build for 1 more second with 2 villagers
	u1._tick_build(1.0)
	u2._tick_build(1.0)
	var progress_after_duo: float = house.build_progress
	# Should have gained 2/15 more progress (both contributing)
	var expected: float = progress_after_solo + 2.0 / 15.0
	assert_float(progress_after_duo).is_equal_approx(expected, 0.001)


func test_multi_villager_completes_faster() -> void:
	## With 3 villagers, a 15s house completes in 5 seconds of game time.
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	var u1 := _create_unit(ctx["scene"], house.position + Vector2(10, 0))
	var u2 := _create_unit(ctx["scene"], house.position + Vector2(-10, 0))
	var u3 := _create_unit(ctx["scene"], house.position + Vector2(0, 10))
	u1._build_target = house
	u2._build_target = house
	u3._build_target = house
	u1._moving = false
	u2._moving = false
	u3._moving = false
	# 3 villagers * 1.0/15.0 = 0.2 per second → 5 seconds to complete
	for i in 5:
		u1._tick_build(1.0)
		u2._tick_build(1.0)
		u3._tick_build(1.0)
	assert_bool(house.under_construction).is_false()
	assert_int(house.hp).is_equal(550)


# ---------------------------------------------------------------------------
# Villager clears target after construction finishes
# ---------------------------------------------------------------------------


func test_villager_clears_build_target_on_completion() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	var u := _create_unit(ctx["scene"], house.position + Vector2(10, 0))
	u._build_target = house
	u._moving = false
	# Complete instantly
	house.apply_build_work(0.99)
	u._tick_build(1.0)
	# Villager should have cleared its build target
	assert_that(u._build_target).is_null()


func test_villager_becomes_idle_after_build_complete() -> void:
	var ctx := _create_scene()
	var house := _place_house(ctx, Vector2i(5, 5))
	var u := _create_unit(ctx["scene"], house.position + Vector2(10, 0))
	u._build_target = house
	u._moving = false
	house.apply_build_work(1.0)
	# Target already complete — next tick should clear
	u._tick_build(1.0)
	assert_bool(u.is_idle()).is_true()
