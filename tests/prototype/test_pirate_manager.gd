extends GdUnitTestSuite
## Tests for pirate_manager.gd — pirate spawning and lifecycle management.

const PirateManagerScript := preload("res://scripts/prototype/pirate_manager.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")

var _config: Dictionary = {
	"enabled": true,
	"trigger_tech": "compass",
	"spawn_interval_seconds": 90,
	"max_active_pirates": 8,
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
	"targets": ["fishing_boat", "trade_barge", "transport_ship"],
	"avoids": ["war_galley", "warship", "dock_with_garrison"],
	"scan_interval": 0.5,
}


class _MockMap:
	extends Node

	var _dims: Vector2i = Vector2i(20, 20)
	var _terrain: Dictionary = {}

	func get_map_dimensions() -> Vector2i:
		return _dims

	func get_terrain_at(pos: Vector2i) -> String:
		return _terrain.get(pos, "grass")


class _MockTargetDetector:
	extends Node

	var _registered: Array = []

	func register_entity(entity: Node2D) -> void:
		_registered.append(entity)

	func unregister_entity(entity: Node2D) -> void:
		_registered.erase(entity)


class _MockTechManager:
	extends Node

	signal tech_researched(player_id: int, tech_id: String, effects: Dictionary)


func _create_manager() -> Node:
	var mgr := Node.new()
	mgr.name = "PirateManager"
	mgr.set_script(PirateManagerScript)
	add_child(mgr)
	auto_free(mgr)
	return mgr


func _create_mock_map(edge_terrain: String = "deep_water") -> _MockMap:
	var map := _MockMap.new()
	add_child(map)
	auto_free(map)
	# Set edge tiles to deep_water
	for x in map._dims.x:
		map._terrain[Vector2i(x, 0)] = edge_terrain
		map._terrain[Vector2i(x, map._dims.y - 1)] = edge_terrain
	for y in range(1, map._dims.y - 1):
		map._terrain[Vector2i(0, y)] = edge_terrain
		map._terrain[Vector2i(map._dims.x - 1, y)] = edge_terrain
	return map


func _create_mock_target_detector() -> _MockTargetDetector:
	var td := _MockTargetDetector.new()
	add_child(td)
	auto_free(td)
	return td


func _create_mock_tech_manager() -> _MockTechManager:
	var tm := _MockTechManager.new()
	add_child(tm)
	auto_free(tm)
	return tm


# -- Init tests --


func test_spawning_disabled_initially() -> void:
	var mgr := _create_manager()
	var map := _create_mock_map()
	var td := _create_mock_target_detector()
	var tm := _create_mock_tech_manager()
	mgr.setup(self, map, td, tm)
	mgr._config = _config
	assert_bool(mgr.is_enabled()).is_false()


func test_compass_research_enables_spawning() -> void:
	var mgr := _create_manager()
	var map := _create_mock_map()
	var td := _create_mock_target_detector()
	var tm := _create_mock_tech_manager()
	mgr.setup(self, map, td, tm)
	mgr._config = _config
	# Simulate compass research
	tm.tech_researched.emit(0, "compass", {})
	assert_bool(mgr.is_enabled()).is_true()


func test_non_compass_tech_does_not_enable() -> void:
	var mgr := _create_manager()
	var map := _create_mock_map()
	var td := _create_mock_target_detector()
	var tm := _create_mock_tech_manager()
	mgr.setup(self, map, td, tm)
	mgr._config = _config
	# Simulate non-compass research
	tm.tech_researched.emit(0, "bronze_working", {})
	assert_bool(mgr.is_enabled()).is_false()


# -- Spawn location tests --


func test_spawns_at_deep_ocean_edge_tiles() -> void:
	var mgr := _create_manager()
	var map := _create_mock_map("deep_water")
	var td := _create_mock_target_detector()
	var tm := _create_mock_tech_manager()
	mgr.setup(self, map, td, tm)
	mgr._config = _config
	var tiles: Array[Vector2i] = mgr._find_deep_ocean_edge_tiles()
	assert_bool(tiles.size() > 0).is_true()
	# All should be on map edges
	for tile in tiles:
		var on_edge: bool = tile.x == 0 or tile.x == map._dims.x - 1 or tile.y == 0 or tile.y == map._dims.y - 1
		assert_bool(on_edge).is_true()


func test_no_spawn_without_deep_water_edges() -> void:
	var mgr := _create_manager()
	var map := _create_mock_map("grass")  # No deep water
	var td := _create_mock_target_detector()
	var tm := _create_mock_tech_manager()
	mgr.setup(self, map, td, tm)
	mgr._config = _config
	var tiles: Array[Vector2i] = mgr._find_deep_ocean_edge_tiles()
	assert_int(tiles.size()).is_equal(0)


# -- Max cap tests --


func test_respects_max_active_pirates_cap() -> void:
	var mgr := _create_manager()
	var map := _create_mock_map()
	var td := _create_mock_target_detector()
	var tm := _create_mock_tech_manager()
	mgr.setup(self, map, td, tm)
	mgr._config = _config.duplicate(true)
	mgr._config["max_active_pirates"] = 2
	mgr._enabled = true
	# Spawn up to max
	mgr._spawn_pirate()
	mgr._spawn_pirate()
	assert_int(mgr.get_active_pirate_count()).is_equal(2)
	# Try to spawn beyond max — timer check would prevent it, but test the cap logic
	mgr._spawn_timer = 100.0
	mgr._process(0.1)
	assert_int(mgr.get_active_pirate_count()).is_equal(2)


# -- Dead pirate cleanup --


func test_dead_pirates_removed_from_active_list() -> void:
	var mgr := _create_manager()
	var map := _create_mock_map()
	var td := _create_mock_target_detector()
	var tm := _create_mock_tech_manager()
	mgr.setup(self, map, td, tm)
	mgr._config = _config
	mgr._enabled = true
	mgr._spawn_pirate()
	assert_int(mgr.get_active_pirate_count()).is_equal(1)
	# Kill the pirate
	var pirate: Node2D = mgr._active_pirates[0]
	pirate.hp = 0
	mgr._clean_dead_pirates()
	assert_int(mgr.get_active_pirate_count()).is_equal(0)


# -- Stats tests --


func test_pirates_have_correct_stats_from_config() -> void:
	var mgr := _create_manager()
	var map := _create_mock_map()
	var td := _create_mock_target_detector()
	var tm := _create_mock_tech_manager()
	mgr.setup(self, map, td, tm)
	mgr._config = _config
	mgr._enabled = true
	mgr._spawn_pirate()
	var pirate: Node2D = mgr._active_pirates[0]
	assert_int(pirate.hp).is_equal(80)
	assert_int(pirate.max_hp).is_equal(80)
	assert_str(pirate.unit_type).is_equal("pirate_ship")
	assert_int(pirate.owner_id).is_equal(-1)
	assert_str(pirate.entity_category).is_equal("pirate")


# -- Spawn interval scaling --


func test_spawn_interval_scales_by_age() -> void:
	var mgr := _create_manager()
	var map := _create_mock_map()
	var td := _create_mock_target_detector()
	var tm := _create_mock_tech_manager()
	mgr.setup(self, map, td, tm)
	mgr._config = _config
	# Age 3 rate = 1.0, so interval = 90/1.0 = 90
	var rate_3: float = mgr._get_age_spawn_rate()
	# Default age is 3 (Medieval)
	assert_float(rate_3).is_equal_approx(1.0, 0.01)


# -- Save / Load --


func test_save_load_round_trip() -> void:
	var mgr := _create_manager()
	var map := _create_mock_map()
	var td := _create_mock_target_detector()
	var tm := _create_mock_tech_manager()
	mgr.setup(self, map, td, tm)
	mgr._config = _config
	mgr._enabled = true
	mgr._spawn_timer = 45.0
	var saved: Dictionary = mgr.save_state()
	# Create fresh manager and load state
	var mgr2 := _create_manager()
	mgr2.setup(self, map, td, tm)
	mgr2._config = _config
	mgr2.load_state(saved)
	assert_bool(mgr2.is_enabled()).is_true()
	assert_float(mgr2._spawn_timer).is_equal_approx(45.0, 0.01)
