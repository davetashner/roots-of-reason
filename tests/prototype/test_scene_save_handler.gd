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


func test_save_state_captures_mid_gather_unit() -> void:
	var u := _add_unit("Gatherer_0", "villager", 0, Vector2(50, 100))
	u._gather_state = 2  # GatherState.GATHERING
	u._gather_type = "wood"
	u._carried_amount = 5
	var state: Dictionary = _handler.save_state()
	var units: Array = state.get("units", [])
	assert_int(units.size()).is_equal(1)
	var ud: Dictionary = units[0]
	assert_int(int(ud.get("gather_state", 0))).is_equal(2)
	assert_str(str(ud.get("gather_type", ""))).is_equal("wood")
	assert_int(int(ud.get("carried_amount", 0))).is_equal(5)


func test_save_state_captures_combat_target_name() -> void:
	var attacker := _add_unit("Attacker_0", "archer", 0, Vector2.ZERO)
	var target := _add_unit("Enemy_0", "archer", 1, Vector2(200, 200))
	target.entity_category = "enemy_unit"
	attacker._combatant.combat_target = target
	attacker._combatant.combat_state = 1  # CombatState.PURSUING
	var state: Dictionary = _handler.save_state()
	var units: Array = state.get("units", [])
	var attacker_data: Dictionary = {}
	for u: Dictionary in units:
		if str(u.get("node_name", "")) == "Attacker_0":
			attacker_data = u
	assert_str(str(attacker_data.get("combat_target_name", ""))).is_equal("Enemy_0")
	assert_int(int(attacker_data.get("combat_state", 0))).is_equal(1)


func test_save_state_captures_build_target() -> void:
	var builder := _add_unit("Builder_0", "villager", 0, Vector2.ZERO)
	var building := Node2D.new()
	building.name = "Building_barracks_5_5"
	building.set_script(BuildingScript)
	building.building_name = "barracks"
	_root.add_child(building)
	builder._build_target = building
	var state: Dictionary = _handler.save_state()
	var units: Array = state.get("units", [])
	assert_str(str(units[0].get("build_target_name", ""))).is_equal("Building_barracks_5_5")


func test_save_state_captures_multiple_units() -> void:
	_add_unit("Unit_0", "villager", 0, Vector2.ZERO)
	_add_unit("Unit_1", "archer", 0, Vector2(100, 0))
	_add_unit("Unit_2", "cavalry", 0, Vector2(200, 0))
	var state: Dictionary = _handler.save_state()
	assert_int(state.get("units", []).size()).is_equal(3)


func test_save_state_preserves_unit_position() -> void:
	_add_unit("Unit_0", "villager", 0, Vector2(123.5, 456.7))
	var state: Dictionary = _handler.save_state()
	var units: Array = state.get("units", [])
	var u: Dictionary = units[0]
	assert_float(float(u.get("position_x", 0))).is_equal_approx(123.5, 0.1)
	assert_float(float(u.get("position_y", 0))).is_equal_approx(456.7, 0.1)


func test_save_state_wolf_goes_to_fauna_not_units() -> void:
	var wolf := _add_unit("Wolf_0", "wolf", -1, Vector2.ZERO)
	wolf.entity_category = "wild_fauna"
	_add_unit("Unit_0", "villager", 0, Vector2.ZERO)
	var state: Dictionary = _handler.save_state()
	assert_int(state.get("fauna", []).size()).is_equal(1)
	assert_int(state.get("units", []).size()).is_equal(1)
	assert_str(str(state.get("fauna", [])[0].get("node_name", ""))).is_equal("Wolf_0")


func test_save_state_with_building_placer() -> void:
	var bp_script := GDScript.new()
	bp_script.source_code = "extends Node\nvar _placed_buildings: Array = []\n"
	bp_script.reload()
	var bp := Node.new()
	bp.name = "BuildingPlacer"
	bp.set_script(bp_script)
	_root.add_child(bp)
	_handler = SceneSaveHandlerScript.new()
	_handler.setup(_root)
	var building := Node2D.new()
	building.name = "Building_house_3_3"
	building.set_script(BuildingScript)
	building.building_name = "house"
	building.grid_pos = Vector2i(3, 3)
	_root.add_child(building)
	bp._placed_buildings.append({"node": building, "building_name": "house", "grid_pos": [3, 3]})
	var state: Dictionary = _handler.save_state()
	assert_int(state.get("buildings_full", []).size()).is_equal(1)
	assert_str(str(state.get("buildings_full", [])[0].get("building_name", ""))).is_equal("house")

# Note: round-trip (load_state) tests are omitted because _teardown_scene_entities
# uses await process_frame which hangs in GdUnit4. Individual entity load_state methods
# are already tested in their respective test files. The save_state tests above verify
# that all entity types are correctly collected and serialized.
