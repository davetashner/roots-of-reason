extends GdUnitTestSuite
## Tests for ExplorerComponent — auto-explore state machine, frontier picking,
## return-to-TC, save/load round trip.

const ExplorerScript := preload("res://scripts/prototype/explorer_component.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")

# -- Mock helpers --


class MockPathfinder:
	extends Node

	var _solid_cells: Dictionary = {}

	func is_cell_solid(cell: Vector2i) -> bool:
		return _solid_cells.has(cell)

	func find_path_world(from: Vector2, to: Vector2) -> Array[Vector2]:
		return [from, to]


class MockVisibilityManager:
	extends Node

	var _explored: Dictionary = {}
	var _map_width: int = 8
	var _map_height: int = 8

	func get_explored_tiles(_player_id: int) -> Dictionary:
		return _explored


class MockTownCenter:
	extends Node2D

	var building_name: String = "town_center"
	var owner_id: int = 0


func _create_unit(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "villager"
	unit.owner_id = 0
	unit.hp = 25
	unit.max_hp = 25
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	var pf := MockPathfinder.new()
	add_child(pf)
	unit._pathfinder = pf
	auto_free(unit)
	auto_free(pf)
	return unit


func _create_vis_manager(explored: Dictionary = {}, w: int = 8, h: int = 8) -> Node:
	var vm := MockVisibilityManager.new()
	vm._explored = explored
	vm._map_width = w
	vm._map_height = h
	add_child(vm)
	auto_free(vm)
	return vm


# -- Tests --


func test_start_exploring_sets_state() -> void:
	var comp := ExplorerScript.new()
	assert_int(comp.explore_state).is_equal(ExplorerScript.ExploreState.NONE)
	comp.start_exploring()
	assert_int(comp.explore_state).is_equal(ExplorerScript.ExploreState.EXPLORING)


func test_cancel_resets_to_none() -> void:
	var comp := ExplorerScript.new()
	comp.start_exploring()
	comp.cancel()
	assert_int(comp.explore_state).is_equal(ExplorerScript.ExploreState.NONE)


func test_tick_skips_when_state_none() -> void:
	var unit := _create_unit()
	var comp: RefCounted = unit._explorer
	# Should not crash or change state when NONE
	comp.tick(0.1)
	assert_int(comp.explore_state).is_equal(ExplorerScript.ExploreState.NONE)


func test_pick_target_finds_frontier_tile() -> void:
	var unit := _create_unit(Vector2.ZERO)
	var comp: RefCounted = unit._explorer
	# Set up a small 4x4 map with origin explored
	var explored: Dictionary = {}
	explored[Vector2i(0, 0)] = true
	explored[Vector2i(1, 0)] = true
	explored[Vector2i(0, 1)] = true
	var vm := _create_vis_manager(explored, 4, 4)
	comp.visibility_manager = vm
	comp.start_exploring()
	# Tick with enough delta to pass retarget interval
	comp.tick(2.0)
	# Unit should be moving now (pathfinder returns a path)
	assert_bool(unit._moving).is_true()


func test_fully_explored_transitions_to_returning() -> void:
	var unit := _create_unit(Vector2.ZERO)
	var comp: RefCounted = unit._explorer
	# Mark ALL tiles as explored in a 2x2 map
	var explored: Dictionary = {}
	for y in 2:
		for x in 2:
			explored[Vector2i(x, y)] = true
	var vm := _create_vis_manager(explored, 2, 2)
	comp.visibility_manager = vm
	# Create a mock TC so returning works
	var tc := _create_mock_tc(Vector2(100, 100))
	comp.start_exploring()
	comp.tick(2.0)
	assert_int(comp.explore_state).is_equal(ExplorerScript.ExploreState.RETURNING_TO_TC)
	tc.queue_free()


func test_returning_to_tc_completes_when_arrived() -> void:
	var unit := _create_unit(Vector2.ZERO)
	var comp: RefCounted = unit._explorer
	comp.explore_state = ExplorerScript.ExploreState.RETURNING_TO_TC
	# Unit is not moving — should complete
	unit._moving = false
	comp.tick(0.1)
	assert_int(comp.explore_state).is_equal(ExplorerScript.ExploreState.NONE)


func test_tick_skips_when_combat_active() -> void:
	var unit := _create_unit(Vector2.ZERO)
	var comp: RefCounted = unit._explorer
	# Set up explored map with frontier
	var explored: Dictionary = {}
	explored[Vector2i(0, 0)] = true
	var vm := _create_vis_manager(explored, 4, 4)
	comp.visibility_manager = vm
	comp.start_exploring()
	# Simulate combat active (combat_state != 0)
	unit._combatant.combat_state = 1  # PURSUING
	comp.tick(2.0)
	# Unit should NOT be moving — tick was skipped
	assert_bool(unit._moving).is_false()


func test_save_load_round_trip() -> void:
	var comp := ExplorerScript.new()
	comp.start_exploring()
	comp._explore_target = Vector2i(5, 3)
	var state := comp.save_state()
	assert_int(int(state.get("explore_state", 0))).is_equal(int(ExplorerScript.ExploreState.EXPLORING))
	assert_int(int(state.get("explore_target_x", -1))).is_equal(5)
	assert_int(int(state.get("explore_target_y", -1))).is_equal(3)
	var comp2 := ExplorerScript.new()
	comp2.load_state(state)
	assert_int(comp2.explore_state).is_equal(ExplorerScript.ExploreState.EXPLORING)
	assert_int(comp2._explore_target.x).is_equal(5)
	assert_int(comp2._explore_target.y).is_equal(3)


func test_save_state_empty_when_none() -> void:
	var comp := ExplorerScript.new()
	var state := comp.save_state()
	assert_bool(state.is_empty()).is_true()


func test_solid_cells_skipped() -> void:
	var unit := _create_unit(Vector2.ZERO)
	var comp: RefCounted = unit._explorer
	# 2x2 map, (0,0) explored, (1,0) solid, (0,1) passable frontier
	var explored: Dictionary = {}
	explored[Vector2i(0, 0)] = true
	var vm := _create_vis_manager(explored, 2, 2)
	comp.visibility_manager = vm
	var pf: MockPathfinder = unit._pathfinder as MockPathfinder
	pf._solid_cells[Vector2i(1, 0)] = true
	comp.start_exploring()
	comp.tick(2.0)
	# Should still find a non-solid frontier tile
	assert_bool(unit._moving).is_true()


# -- Helper: create mock town center --


func _create_mock_tc(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var tc := MockTownCenter.new()
	tc.position = pos
	add_child(tc)
	auto_free(tc)
	return tc
