extends GdUnitTestSuite
## Tests for building_placer.gd — building placement system.

const PlacerScript := preload("res://scripts/prototype/building_placer.gd")
const MapScript := preload("res://scripts/prototype/prototype_map.gd")
const PathfindingScript := preload("res://scripts/prototype/pathfinding_grid.gd")
const TargetDetectorScript := preload("res://scripts/prototype/target_detector.gd")

var _original_age: int = 0


func before() -> void:
	_original_age = GameManager.current_age


func after() -> void:
	GameManager.current_age = _original_age


func _build_grass_grid(size: int) -> Dictionary:
	var grid: Dictionary = {}
	for x in size:
		for y in size:
			grid[Vector2i(x, y)] = "grass"
	return grid


func _default_costs() -> Dictionary:
	return {"grass": 1.0, "forest": 2.0, "desert": 1.5, "water": -1}


func _create_placer() -> Node:
	var scene := Node2D.new()
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
	pf.build(20, map._tile_grid, _default_costs())
	# Target detector
	var td := Node.new()
	td.name = "TargetDetector"
	td.set_script(TargetDetectorScript)
	scene.add_child(td)
	# Camera
	var cam := Camera2D.new()
	cam.name = "Camera"
	scene.add_child(cam)
	# Placer
	var placer := Node.new()
	placer.name = "BuildingPlacer"
	placer.set_script(PlacerScript)
	scene.add_child(placer)
	placer.setup(cam, pf, map, td)
	# Init player resources
	var starting: Dictionary = {
		ResourceManager.ResourceType.WOOD: 1000,
		ResourceManager.ResourceType.STONE: 500,
		ResourceManager.ResourceType.FOOD: 200,
		ResourceManager.ResourceType.GOLD: 200,
	}
	ResourceManager.init_player(0, starting)
	return placer


# -- Lifecycle --


func test_start_placement_activates() -> void:
	var placer := _create_placer()
	var result: bool = placer.start_placement("house", 0)
	assert_bool(result).is_true()
	assert_bool(placer.is_active()).is_true()


func test_cancel_placement_deactivates() -> void:
	var placer := _create_placer()
	placer.start_placement("house", 0)
	placer.cancel_placement()
	assert_bool(placer.is_active()).is_false()


func test_start_placement_emits_signal() -> void:
	var placer := _create_placer()
	var monitor := monitor_signals(placer)
	placer.start_placement("house", 0)
	await assert_signal(monitor).is_emitted("placement_started", ["house"])


func test_cancel_placement_emits_signal() -> void:
	var placer := _create_placer()
	placer.start_placement("house", 0)
	var monitor := monitor_signals(placer)
	placer.cancel_placement()
	await assert_signal(monitor).is_emitted("placement_cancelled", ["house"])


# -- Ghost --


func test_ghost_created_on_start() -> void:
	var placer := _create_placer()
	placer.start_placement("house", 0)
	assert_bool(placer._ghost != null).is_true()


func test_ghost_removed_on_cancel() -> void:
	var placer := _create_placer()
	placer.start_placement("house", 0)
	placer.cancel_placement()
	# Ghost is queue_freed, check _ghost reference cleared
	assert_bool(placer._ghost == null).is_true()


# -- Resource deduction --


func test_confirm_deducts_resources() -> void:
	var placer := _create_placer()
	var wood_start: Dictionary = {ResourceManager.ResourceType.WOOD: 100}
	ResourceManager.init_player(0, wood_start)
	placer.start_placement("house", 0)
	# Simulate valid placement
	placer._current_grid_pos = Vector2i(5, 5)
	placer._is_valid = true
	placer._confirm_placement()
	# House costs 25 wood
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.WOOD)).is_equal(75)


# -- Cells marked solid --


func test_cells_marked_solid_after_placement() -> void:
	var placer := _create_placer()
	placer.start_placement("house", 0)
	placer._current_grid_pos = Vector2i(5, 5)
	placer._is_valid = true
	placer._confirm_placement()
	# House is 2x2 — cells (5,5), (6,5), (5,6), (6,6) should be solid
	var pf: Node = placer._pathfinder
	assert_bool(pf.is_cell_solid(Vector2i(5, 5))).is_true()
	assert_bool(pf.is_cell_solid(Vector2i(6, 5))).is_true()
	assert_bool(pf.is_cell_solid(Vector2i(5, 6))).is_true()
	assert_bool(pf.is_cell_solid(Vector2i(6, 6))).is_true()


# -- Affordability --


func test_cannot_start_if_unaffordable() -> void:
	var placer := _create_placer()
	var no_wood: Dictionary = {ResourceManager.ResourceType.WOOD: 0}
	ResourceManager.init_player(0, no_wood)
	var result: bool = placer.start_placement("house", 0)
	assert_bool(result).is_false()
	assert_bool(placer.is_active()).is_false()


# -- Save/Load --


func test_save_load_round_trip() -> void:
	var placer := _create_placer()
	placer.start_placement("house", 0)
	placer._current_grid_pos = Vector2i(5, 5)
	placer._is_valid = true
	placer._confirm_placement()
	var state: Dictionary = placer.save_state()
	assert_int(state["placed_buildings"].size()).is_equal(1)
	assert_str(state["placed_buildings"][0]["building_name"]).is_equal("house")
	# Create a new placer and load state
	var placer2 := _create_placer()
	var reload_wood: Dictionary = {ResourceManager.ResourceType.WOOD: 1000}
	ResourceManager.init_player(0, reload_wood)
	placer2.load_state(state)
	assert_int(placer2._placed_buildings.size()).is_equal(1)


# -- Parse costs --


func test_parse_costs_maps_strings_to_enum() -> void:
	var placer := _create_placer()
	var raw: Dictionary = {"wood": 100, "stone": 50}
	var parsed: Dictionary = placer._parse_costs(raw)
	assert_bool(parsed.has(ResourceManager.ResourceType.WOOD)).is_true()
	assert_int(parsed[ResourceManager.ResourceType.WOOD]).is_equal(100)
	assert_bool(parsed.has(ResourceManager.ResourceType.STONE)).is_true()
	assert_int(parsed[ResourceManager.ResourceType.STONE]).is_equal(50)


# -- Age gate --


func test_start_placement_fails_when_age_too_low() -> void:
	var placer := _create_placer()
	GameManager.current_age = 0
	# Market requires age 1
	var result: bool = placer.start_placement("market", 0)
	assert_bool(result).is_false()
	assert_bool(placer.is_active()).is_false()


func test_start_placement_succeeds_at_correct_age() -> void:
	var placer := _create_placer()
	GameManager.current_age = 1
	# Market requires age 1
	var result: bool = placer.start_placement("market", 0)
	assert_bool(result).is_true()
	assert_bool(placer.is_active()).is_true()


# -- Prerequisite checks --


class MockTechManager:
	extends Node
	var _researched: Dictionary = {}

	func is_tech_researched(tech_id: String, _player_id: int = 0) -> bool:
		return _researched.has(tech_id)

	func mark_researched(tech_id: String) -> void:
		_researched[tech_id] = true


func _create_placer_with_tech_manager() -> Array:
	var placer := _create_placer()
	var tm := MockTechManager.new()
	tm.name = "MockTechManager"
	add_child(tm)
	auto_free(tm)
	placer._tech_manager = tm
	return [placer, tm]


func test_required_techs_blocks_placement() -> void:
	var pair := _create_placer_with_tech_manager()
	var placer: Node = pair[0]
	GameManager.current_age = 6
	var starting: Dictionary = {
		ResourceManager.ResourceType.KNOWLEDGE: 99999,
		ResourceManager.ResourceType.GOLD: 99999,
		ResourceManager.ResourceType.STONE: 99999,
	}
	ResourceManager.init_player(0, starting)
	# AGI Core requires agi_core tech — not researched
	var result: bool = placer.start_placement("agi_core", 0)
	assert_bool(result).is_false()


func test_required_techs_allows_placement() -> void:
	var pair := _create_placer_with_tech_manager()
	var placer: Node = pair[0]
	var tm: MockTechManager = pair[1]
	GameManager.current_age = 6
	var starting: Dictionary = {
		ResourceManager.ResourceType.KNOWLEDGE: 99999,
		ResourceManager.ResourceType.GOLD: 99999,
		ResourceManager.ResourceType.STONE: 99999,
	}
	ResourceManager.init_player(0, starting)
	# Research the required tech
	tm.mark_researched("agi_core")
	tm.mark_researched("transformer_architecture")
	# AGI Core requires transformer_lab building (singularity chain)
	# First place gpu_foundry (needed for transformer_lab)
	placer.start_placement("gpu_foundry", 0)
	placer._current_grid_pos = Vector2i(2, 2)
	placer._is_valid = true
	placer._confirm_placement()
	for entry: Dictionary in placer._placed_buildings:
		var node: Node2D = entry.get("node")
		if is_instance_valid(node) and node.building_name == "gpu_foundry":
			node.under_construction = false
	# Then place transformer_lab (needed for agi_core)
	placer.start_placement("transformer_lab", 0)
	placer._current_grid_pos = Vector2i(6, 2)
	placer._is_valid = true
	placer._confirm_placement()
	for entry: Dictionary in placer._placed_buildings:
		var node: Node2D = entry.get("node")
		if is_instance_valid(node) and node.building_name == "transformer_lab":
			node.under_construction = false
	# Now AGI Core should be placeable
	var result: bool = placer.start_placement("agi_core", 0)
	assert_bool(result).is_true()


func test_required_buildings_blocks_placement() -> void:
	var pair := _create_placer_with_tech_manager()
	var placer: Node = pair[0]
	var tm: MockTechManager = pair[1]
	GameManager.current_age = 6
	var starting: Dictionary = {
		ResourceManager.ResourceType.KNOWLEDGE: 99999,
		ResourceManager.ResourceType.GOLD: 99999,
		ResourceManager.ResourceType.STONE: 99999,
	}
	ResourceManager.init_player(0, starting)
	tm.mark_researched("agi_core")
	# No gpu_foundry built — should fail
	var result: bool = placer.start_placement("agi_core", 0)
	assert_bool(result).is_false()


func test_required_buildings_allows_when_built() -> void:
	var pair := _create_placer_with_tech_manager()
	var placer: Node = pair[0]
	var tm: MockTechManager = pair[1]
	GameManager.current_age = 6
	var starting: Dictionary = {
		ResourceManager.ResourceType.KNOWLEDGE: 99999,
		ResourceManager.ResourceType.GOLD: 99999,
		ResourceManager.ResourceType.STONE: 99999,
	}
	ResourceManager.init_player(0, starting)
	tm.mark_researched("agi_core")
	tm.mark_researched("transformer_architecture")
	# Build gpu_foundry first (needed for transformer_lab)
	placer.start_placement("gpu_foundry", 0)
	placer._current_grid_pos = Vector2i(2, 2)
	placer._is_valid = true
	placer._confirm_placement()
	for entry: Dictionary in placer._placed_buildings:
		var node: Node2D = entry.get("node")
		if is_instance_valid(node) and node.building_name == "gpu_foundry":
			node.under_construction = false
	# Build transformer_lab (needed for agi_core)
	placer.start_placement("transformer_lab", 0)
	placer._current_grid_pos = Vector2i(6, 2)
	placer._is_valid = true
	placer._confirm_placement()
	for entry: Dictionary in placer._placed_buildings:
		var node: Node2D = entry.get("node")
		if is_instance_valid(node) and node.building_name == "transformer_lab":
			node.under_construction = false
	var result: bool = placer.start_placement("agi_core", 0)
	assert_bool(result).is_true()


# -- is_building_unlocked --


func test_is_building_unlocked_returns_true_for_age_zero_building() -> void:
	var placer := _create_placer()
	GameManager.current_age = 0
	var unlocked: bool = placer.is_building_unlocked("house", 0)
	assert_bool(unlocked).is_true()


func test_is_building_unlocked_returns_false_when_age_too_low() -> void:
	var placer := _create_placer()
	GameManager.current_age = 0
	var unlocked: bool = placer.is_building_unlocked("barracks", 0)
	assert_bool(unlocked).is_false()


func test_is_building_unlocked_returns_true_at_correct_age() -> void:
	var placer := _create_placer()
	GameManager.current_age = 1
	var unlocked: bool = placer.is_building_unlocked("barracks", 0)
	assert_bool(unlocked).is_true()


func test_is_building_unlocked_ignores_affordability() -> void:
	var placer := _create_placer()
	GameManager.current_age = 0
	# Zero out resources — unlock check should still pass
	var no_res: Dictionary = {ResourceManager.ResourceType.WOOD: 0}
	ResourceManager.init_player(0, no_res)
	var unlocked: bool = placer.is_building_unlocked("house", 0)
	assert_bool(unlocked).is_true()


func test_is_building_unlocked_checks_required_techs() -> void:
	var pair := _create_placer_with_tech_manager()
	var placer: Node = pair[0]
	GameManager.current_age = 5
	# nuclear_plant requires nuclear_fission tech
	var unlocked: bool = placer.is_building_unlocked("nuclear_plant", 0)
	assert_bool(unlocked).is_false()
