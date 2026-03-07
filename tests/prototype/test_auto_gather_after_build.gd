extends GdUnitTestSuite
## Tests for auto-gather behavior after completing a drop-off building.

const GFC := preload("res://scripts/prototype/game_flow_controller.gd")
const EntityRegistry := preload("res://scripts/prototype/entity_registry.gd")
const BuildingFactory := preload("res://tests/helpers/building_factory.gd")
const ResourceFactory := preload("res://tests/helpers/resource_factory.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const GathererComponentScript := preload("res://scripts/prototype/gatherer_component.gd")

var _root: Node2D
var _gfc: GFC
var _registry: EntityRegistry


class MockRoot:
	extends Node2D

	var _entity_registry: RefCounted = null
	var _population_manager: Node = null
	var _game_stats_tracker: Node = null
	var _tech_manager: Node = null
	var _building_placer: Node = null
	var _notification_panel: Node = null
	var _singularity_cinematic: Node = null


class MockBootstrapper:
	extends RefCounted

	func try_attach_production_queue(_b: Node2D) -> void:
		pass


func before_test() -> void:
	_registry = EntityRegistry.new()
	_root = MockRoot.new()
	_root._entity_registry = _registry
	add_child(_root)
	auto_free(_root)
	_gfc = GFC.new()
	_gfc.setup(_root, MockBootstrapper.new())


func _make_villager(pos: Vector2 = Vector2.ZERO, owner_id: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.name = "Villager_%d" % _root.get_child_count()
	unit.set_script(UnitScript)
	unit.unit_type = "villager"
	unit.owner_id = owner_id
	unit.position = pos
	_root.add_child(unit)
	auto_free(unit)
	unit._scene_root = _root
	_registry.register(unit)
	return unit


func _make_building(
	building_name: String,
	pos: Vector2,
	drop_off_types: Array[String],
	owner_id: int = 0,
) -> Node2D:
	var b := (
		BuildingFactory
		. create_drop_off(
			{
				building_name = building_name,
				position = pos,
				drop_off_types = drop_off_types,
				owner_id = owner_id,
			}
		)
	)
	_root.add_child(b)
	auto_free(b)
	return b


func _make_resource(
	pos: Vector2,
	res_type: String,
	res_name: String = "",
) -> Node2D:
	var actual_name: String = res_name if res_name != "" else res_type
	var n := (
		ResourceFactory
		. create_resource_node(
			{
				position = pos,
				resource_type = res_type,
				resource_name = actual_name,
			}
		)
	)
	_root.add_child(n)
	auto_free(n)
	return n


# ---------------------------------------------------------------------------
# Lumber camp -> wood
# ---------------------------------------------------------------------------


func test_lumber_camp_sends_builders_to_nearest_wood() -> void:
	var building := _make_building("lumber_camp", Vector2(100, 0), ["wood"] as Array[String])
	var tree := _make_resource(Vector2(150, 0), "wood", "tree")
	var villager := _make_villager(Vector2(100, 0))
	villager._build_target = building
	_gfc.on_building_construction_complete(building)
	var gc: GathererComponentScript = villager._gatherer
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)
	assert_object(gc.gather_target).is_same(tree)


# ---------------------------------------------------------------------------
# Mining camp -> stone/gold (nearest wins)
# ---------------------------------------------------------------------------


func test_mining_camp_sends_builders_to_nearest_stone_or_gold() -> void:
	var building := _make_building("mining_camp", Vector2(100, 0), ["stone", "gold"] as Array[String])
	_make_resource(Vector2(300, 0), "stone", "stone_mine")
	var near_gold := _make_resource(Vector2(120, 0), "gold", "gold_mine")
	var villager := _make_villager(Vector2(100, 0))
	villager._build_target = building
	_gfc.on_building_construction_complete(building)
	var gc: GathererComponentScript = villager._gatherer
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)
	assert_object(gc.gather_target).is_same(near_gold)


# ---------------------------------------------------------------------------
# Granary -> food
# ---------------------------------------------------------------------------


func test_granary_sends_builders_to_nearest_food() -> void:
	var building := _make_building("granary", Vector2(100, 0), ["food"] as Array[String])
	var bush := _make_resource(Vector2(130, 0), "food", "berry_bush")
	var villager := _make_villager(Vector2(100, 0))
	villager._build_target = building
	_gfc.on_building_construction_complete(building)
	var gc: GathererComponentScript = villager._gatherer
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)
	assert_object(gc.gather_target).is_same(bush)


# ---------------------------------------------------------------------------
# Multiple builders
# ---------------------------------------------------------------------------


func test_multiple_builders_all_auto_gather() -> void:
	var building := _make_building("lumber_camp", Vector2(100, 0), ["wood"] as Array[String])
	var tree := _make_resource(Vector2(150, 0), "wood", "tree")
	var v1 := _make_villager(Vector2(100, 0))
	var v2 := _make_villager(Vector2(105, 0))
	v1._build_target = building
	v2._build_target = building
	_gfc.on_building_construction_complete(building)
	assert_object(v1._gatherer.gather_target).is_same(tree)
	assert_object(v2._gatherer.gather_target).is_same(tree)


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------


func test_non_drop_off_building_does_not_auto_gather() -> void:
	var building := (
		BuildingFactory
		. create_building(
			{
				building_name = "house",
				position = Vector2(100, 0),
			}
		)
	)
	_root.add_child(building)
	auto_free(building)
	_make_resource(Vector2(150, 0), "wood", "tree")
	var villager := _make_villager(Vector2(100, 0))
	villager._build_target = building
	_gfc.on_building_construction_complete(building)
	assert_int(villager._gatherer.gather_state).is_equal(GathererComponentScript.GatherState.NONE)


func test_no_nearby_resource_leaves_villager_idle() -> void:
	var building := _make_building("lumber_camp", Vector2(100, 0), ["wood"] as Array[String])
	# No wood resources in scene
	var villager := _make_villager(Vector2(100, 0))
	villager._build_target = building
	_gfc.on_building_construction_complete(building)
	assert_int(villager._gatherer.gather_state).is_equal(GathererComponentScript.GatherState.NONE)


func test_idle_villager_not_building_is_not_assigned() -> void:
	var building := _make_building("lumber_camp", Vector2(100, 0), ["wood"] as Array[String])
	_make_resource(Vector2(150, 0), "wood", "tree")
	var villager := _make_villager(Vector2(500, 0))
	# Villager is idle, NOT building this structure
	_gfc.on_building_construction_complete(building)
	assert_int(villager._gatherer.gather_state).is_equal(GathererComponentScript.GatherState.NONE)
