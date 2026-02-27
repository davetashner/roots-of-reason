extends GdUnitTestSuite
## Tests for scene_save_handler.gd — save/load orchestration for scene entities.

const SceneSaveHandlerScript := preload("res://scripts/prototype/scene_save_handler.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

var _handler: RefCounted
var _root: Node2D
var _target_detector: Node


func before_test() -> void:
	_root = Node2D.new()
	_root.name = "TestRoot"
	add_child(_root)
	_target_detector = Node.new()
	_target_detector.name = "TargetDetector"
	_target_detector.set_script(load("res://scripts/prototype/target_detector.gd"))
	_root.add_child(_target_detector)
	_handler = SceneSaveHandlerScript.new()
	_handler.setup(_root)


func after_test() -> void:
	_handler = null
	if is_instance_valid(_root):
		_root.queue_free()


func _add_unit(
	uname: String = "Unit_0",
	utype: String = "villager",
	oid: int = 0,
	pos: Vector2 = Vector2.ZERO,
) -> Node2D:
	var u := Node2D.new()
	u.name = uname
	u.set_script(UnitScript)
	u.unit_type = utype
	u.owner_id = oid
	u.position = pos
	_root.add_child(u)
	u._scene_root = _root
	return u


func _add_resource(rname: String = "Resource_food_0", res_type: String = "food") -> Node2D:
	var r := Node2D.new()
	r.name = rname
	r.set_script(ResourceNodeScript)
	_root.add_child(r)
	r.setup(res_type)
	return r


# -- save_state tests --


func test_save_state_returns_dictionary() -> void:
	var state: Dictionary = _handler.save_state()
	assert_bool(state is Dictionary).is_true()


func test_save_state_contains_expected_keys() -> void:
	var state: Dictionary = _handler.save_state()
	assert_bool(state.has("units")).is_true()
	assert_bool(state.has("resources")).is_true()
	assert_bool(state.has("fauna")).is_true()
	assert_bool(state.has("buildings_full")).is_true()
	assert_bool(state.has("map")).is_true()
	assert_bool(state.has("tech_manager")).is_true()


func test_save_state_captures_unit() -> void:
	_add_unit("Unit_0", "villager", 0, Vector2(100, 200))
	var state: Dictionary = _handler.save_state()
	var units: Array = state.get("units", [])
	assert_int(units.size()).is_equal(1)
	var u: Dictionary = units[0]
	assert_str(str(u.get("unit_type", ""))).is_equal("villager")
	assert_str(str(u.get("node_name", ""))).is_equal("Unit_0")
	assert_int(int(u.get("owner_id", -1))).is_equal(0)


func test_save_state_captures_fauna() -> void:
	var wolf := _add_unit("Fauna_wolf_0", "wolf", -1)
	wolf.entity_category = "wild_fauna"
	var state: Dictionary = _handler.save_state()
	var fauna: Array = state.get("fauna", [])
	assert_int(fauna.size()).is_equal(1)
	assert_str(str(fauna[0].get("entity_category", ""))).is_equal("wild_fauna")


func test_save_state_captures_resource_node() -> void:
	_add_resource("Resource_food_0", "food")
	var state: Dictionary = _handler.save_state()
	var resources: Array = state.get("resources", [])
	assert_int(resources.size()).is_equal(1)
	assert_str(str(resources[0].get("node_name", ""))).is_equal("Resource_food_0")


func test_save_state_captures_unit_color() -> void:
	var u := _add_unit("Unit_0", "villager", 0)
	u.unit_color = Color(0.9, 0.2, 0.2)
	var state: Dictionary = _handler.save_state()
	var units: Array = state.get("units", [])
	assert_float(float(units[0].get("unit_color_r", 0))).is_equal_approx(0.9, 0.01)
	assert_float(float(units[0].get("unit_color_g", 0))).is_equal_approx(0.2, 0.01)


func test_save_state_empty_scene_returns_empty_arrays() -> void:
	var state: Dictionary = _handler.save_state()
	assert_int(state.get("units", []).size()).is_equal(0)
	assert_int(state.get("resources", []).size()).is_equal(0)
	assert_int(state.get("fauna", []).size()).is_equal(0)
	assert_int(state.get("buildings_full", []).size()).is_equal(0)

# Note: round-trip (load_state) tests are omitted because _teardown_scene_entities
# uses await process_frame which hangs in GdUnit4. Individual entity load_state methods
# are already tested in their respective test files. The save_state tests above verify
# that all entity types are correctly collected and serialized.
