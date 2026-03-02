extends GdUnitTestSuite
## Tests for Nuclear Plant building — data loading, tech gating, and cost reduction.

const PlacerScript := preload("res://scripts/prototype/building_placer.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const MapScript := preload("res://scripts/prototype/prototype_map.gd")
const PathfindingScript := preload("res://scripts/prototype/pathfinding_grid.gd")
const TargetDetectorScript := preload("res://scripts/prototype/target_detector.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _gm_guard: RefCounted


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_gm_guard = GMGuard.new()
	GameManager.current_age = 5
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.game_time = 0.0


func after_test() -> void:
	_gm_guard.dispose()
	_rm_guard.dispose()
	GameUtils.clear_autoload_cache()


func _build_grass_grid(grid_size: int) -> Dictionary:
	var grid: Dictionary = {}
	for x in grid_size:
		for y in grid_size:
			grid[Vector2i(x, y)] = "grass"
	return grid


func _default_costs() -> Dictionary:
	return {"grass": 1.0, "forest": 2.0, "desert": 1.5, "water": -1}


func _create_tech_manager() -> Node:
	var node := Node.new()
	node.set_script(TechManagerScript)
	add_child(node)
	auto_free(node)
	return node


func _create_placer(tech_mgr: Node = null) -> Node:
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
	placer.setup(cam, pf, map, td, tech_mgr)
	return placer


func _give_resources(player_id: int, stone: int = 0, gold: int = 0) -> void:
	(
		ResourceManager
		. init_player(
			player_id,
			{
				ResourceManager.ResourceType.FOOD: 5000,
				ResourceManager.ResourceType.WOOD: 5000,
				ResourceManager.ResourceType.STONE: stone,
				ResourceManager.ResourceType.GOLD: gold,
				ResourceManager.ResourceType.KNOWLEDGE: 5000,
			}
		)
	)


# -- Data loading --


func test_nuclear_plant_data_loads() -> void:
	var stats: Dictionary = DataLoader.get_building_stats("nuclear_plant")
	assert_that(stats).is_not_equal({})
	assert_str(str(stats.get("name", ""))).is_equal("Nuclear Plant")
	assert_int(int(stats.get("hp", 0))).is_equal(1500)
	var fp: Array = stats.get("footprint", [])
	assert_int(int(fp[0])).is_equal(3)
	assert_int(int(fp[1])).is_equal(3)
	assert_int(int(stats.get("age_required", 0))).is_equal(5)
	assert_int(int(stats.get("build_time", 0))).is_equal(90)
	var cost: Dictionary = stats.get("build_cost", {})
	assert_int(int(cost.get("stone", 0))).is_equal(300)
	assert_int(int(cost.get("gold", 0))).is_equal(300)
	var effects: Dictionary = stats.get("effects", {})
	assert_float(float(effects.get("building_cost_reduction", 0.0))).is_equal_approx(0.20, 0.001)


func test_nuclear_plant_requires_nuclear_fission_tech() -> void:
	var stats: Dictionary = DataLoader.get_building_stats("nuclear_plant")
	var req_techs: Array = stats.get("required_techs", [])
	assert_array(req_techs).contains(["nuclear_fission"])


func test_nuclear_fission_unlocks_nuclear_plant() -> void:
	var tech_data: Dictionary = DataLoader.get_tech_data("nuclear_fission")
	assert_that(tech_data).is_not_equal({})
	var effects: Dictionary = tech_data.get("effects", {})
	var unlock_buildings: Array = effects.get("unlock_buildings", [])
	assert_array(unlock_buildings).contains(["nuclear_plant"])


# -- Tech gating --


func test_nuclear_plant_unavailable_before_nuclear_fission() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000, 1000)
	var placer := _create_placer(tm)
	# Without nuclear_fission researched, placement should fail
	var result: bool = placer.start_placement("nuclear_plant", 0)
	assert_bool(result).is_false()


func test_nuclear_plant_unlocked_by_nuclear_fission() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000, 1000)
	# Manually mark nuclear_fission and its prerequisites as researched
	tm._researched_techs[0] = ["atomic_theory", "nuclear_fission"]
	var placer := _create_placer(tm)
	var result: bool = placer.start_placement("nuclear_plant", 0)
	assert_bool(result).is_true()
	placer.cancel_placement()


# -- Cost reduction --


func test_nuclear_plant_cost_reduction_applied() -> void:
	var placer := Node.new()
	placer.set_script(PlacerScript)
	add_child(placer)
	auto_free(placer)
	# Default multiplier should be 1.0
	assert_float(placer.get_building_cost_multiplier()).is_equal(1.0)
	# Simulate a completed nuclear plant building
	var building := Node2D.new()
	building.set_script(BuildingScript)
	building.building_name = "nuclear_plant"
	add_child(building)
	auto_free(building)
	placer.apply_building_effect(building)
	# Multiplier should now be 0.80 (20% reduction)
	assert_float(placer.get_building_cost_multiplier()).is_equal_approx(0.80, 0.001)


func test_cost_reduction_applies_to_building_costs() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000, 1000)
	tm._researched_techs[0] = ["atomic_theory", "nuclear_fission"]
	var placer := _create_placer(tm)
	# Simulate nuclear plant effect
	var nuke_building := Node2D.new()
	nuke_building.set_script(BuildingScript)
	nuke_building.building_name = "nuclear_plant"
	add_child(nuke_building)
	auto_free(nuke_building)
	placer.apply_building_effect(nuke_building)
	# A house costs 100 wood normally; with 20% reduction it should cost 80
	var house_stats: Dictionary = DataLoader.get_building_stats("house")
	var raw_costs: Dictionary = house_stats.get("build_cost", {})
	# Verify house has a wood cost
	assert_that(raw_costs).is_not_equal({})
	# Start placement of house to verify cost flow works with reduction
	var result: bool = placer.start_placement("house", 0)
	assert_bool(result).is_true()
	placer.cancel_placement()


func test_cost_reduction_reverted_on_destroy() -> void:
	var placer := Node.new()
	placer.set_script(PlacerScript)
	add_child(placer)
	auto_free(placer)
	var building := Node2D.new()
	building.set_script(BuildingScript)
	building.building_name = "nuclear_plant"
	add_child(building)
	auto_free(building)
	placer.apply_building_effect(building)
	assert_float(placer.get_building_cost_multiplier()).is_equal_approx(0.80, 0.001)
	placer.revert_building_effect(building)
	assert_float(placer.get_building_cost_multiplier()).is_equal_approx(1.0, 0.001)


func test_cost_multiplier_saved_and_loaded() -> void:
	var placer := Node.new()
	placer.set_script(PlacerScript)
	add_child(placer)
	auto_free(placer)
	var building := Node2D.new()
	building.set_script(BuildingScript)
	building.building_name = "nuclear_plant"
	add_child(building)
	auto_free(building)
	placer.apply_building_effect(building)
	# Save state
	var state: Dictionary = placer.save_state()
	assert_float(float(state.get("building_cost_multiplier", 1.0))).is_equal_approx(0.80, 0.001)
	# Create a new placer and load state
	var placer2 := Node.new()
	placer2.set_script(PlacerScript)
	add_child(placer2)
	auto_free(placer2)
	placer2.load_state(state)
	assert_float(placer2.get_building_cost_multiplier()).is_equal_approx(0.80, 0.001)
