extends GdUnitTestSuite
## Tests for EntityRegistry.

const EntityRegistryScript := preload("res://scripts/prototype/entity_registry.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

# --- Helpers ---


func _create_registry() -> RefCounted:
	return EntityRegistryScript.new()


func _create_unit(
	owner_id: int = 0,
	unit_category: String = "",
	entity_category: String = "",
) -> Node2D:
	var unit: Node2D = auto_free(Node2D.new())
	unit.set_script(UnitScript)
	unit.owner_id = owner_id
	unit.unit_category = unit_category
	unit.entity_category = entity_category
	return unit


func _create_building(owner_id: int = 0, bname: String = "barracks") -> Node2D:
	var building: Node2D = auto_free(Node2D.new())
	building.set_script(BuildingScript)
	building.owner_id = owner_id
	building.building_name = bname
	return building


# --- register / unregister basics ---


func test_register_increments_count() -> void:
	var reg := _create_registry()
	assert_int(reg.get_count()).is_equal(0)
	var unit := _create_unit(0, "military")
	reg.register(unit)
	assert_int(reg.get_count()).is_equal(1)


func test_double_register_is_idempotent() -> void:
	var reg := _create_registry()
	var unit := _create_unit(0, "military")
	reg.register(unit)
	reg.register(unit)
	assert_int(reg.get_count()).is_equal(1)


func test_unregister_decrements_count() -> void:
	var reg := _create_registry()
	var unit := _create_unit(0, "military")
	reg.register(unit)
	reg.unregister(unit)
	assert_int(reg.get_count()).is_equal(0)


func test_unregister_unregistered_entity_is_noop() -> void:
	var reg := _create_registry()
	var unit := _create_unit()
	reg.unregister(unit)
	assert_int(reg.get_count()).is_equal(0)


func test_is_registered() -> void:
	var reg := _create_registry()
	var unit := _create_unit(0, "military")
	assert_bool(reg.is_registered(unit)).is_false()
	reg.register(unit)
	assert_bool(reg.is_registered(unit)).is_true()
	reg.unregister(unit)
	assert_bool(reg.is_registered(unit)).is_false()


# --- get_by_owner ---


func test_get_by_owner_returns_matching_entities() -> void:
	var reg := _create_registry()
	var u0 := _create_unit(0, "military")
	var u1 := _create_unit(1, "military")
	var u0b := _create_unit(0, "villager")
	reg.register(u0)
	reg.register(u1)
	reg.register(u0b)
	var result: Array[Node2D] = reg.get_by_owner(0)
	assert_int(result.size()).is_equal(2)
	assert_bool(result.has(u0)).is_true()
	assert_bool(result.has(u0b)).is_true()
	assert_bool(result.has(u1)).is_false()


func test_get_by_owner_unknown_returns_empty() -> void:
	var reg := _create_registry()
	var result: Array[Node2D] = reg.get_by_owner(99)
	assert_int(result.size()).is_equal(0)


# --- get_by_category ---


func test_get_by_category_returns_matching_entities() -> void:
	var reg := _create_registry()
	var mil := _create_unit(0, "military")
	var vil := _create_unit(0, "villager")
	reg.register(mil)
	reg.register(vil)
	var result: Array[Node2D] = reg.get_by_category("military")
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has(mil)).is_true()


func test_get_by_category_unknown_returns_empty() -> void:
	var reg := _create_registry()
	var result: Array[Node2D] = reg.get_by_category("nonexistent")
	assert_int(result.size()).is_equal(0)


func test_building_category_resolved_as_building() -> void:
	var reg := _create_registry()
	var bld := _create_building(0, "barracks")
	reg.register(bld)
	var result: Array[Node2D] = reg.get_by_category("building")
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has(bld)).is_true()


# --- get_by_owner_and_category ---


func test_get_by_owner_and_category() -> void:
	var reg := _create_registry()
	var p0_mil := _create_unit(0, "military")
	var p0_vil := _create_unit(0, "villager")
	var p1_mil := _create_unit(1, "military")
	reg.register(p0_mil)
	reg.register(p0_vil)
	reg.register(p1_mil)
	var result: Array[Node2D] = reg.get_by_owner_and_category(0, "military")
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has(p0_mil)).is_true()


func test_get_by_owner_and_category_unknown_returns_empty() -> void:
	var reg := _create_registry()
	var result: Array[Node2D] = reg.get_by_owner_and_category(0, "siege")
	assert_int(result.size()).is_equal(0)


# --- count helpers ---


func test_get_count_by_owner() -> void:
	var reg := _create_registry()
	var u0 := _create_unit(0, "military")
	var u1 := _create_unit(1, "military")
	reg.register(u0)
	reg.register(u1)
	assert_int(reg.get_count_by_owner(0)).is_equal(1)
	assert_int(reg.get_count_by_owner(1)).is_equal(1)
	assert_int(reg.get_count_by_owner(99)).is_equal(0)


func test_get_count_by_owner_and_category() -> void:
	var reg := _create_registry()
	var mil := _create_unit(0, "military")
	var vil := _create_unit(0, "villager")
	reg.register(mil)
	reg.register(vil)
	assert_int(reg.get_count_by_owner_and_category(0, "military")).is_equal(1)
	assert_int(reg.get_count_by_owner_and_category(0, "villager")).is_equal(1)
	assert_int(reg.get_count_by_owner_and_category(0, "archer")).is_equal(0)


# --- clear ---


func test_clear_removes_all() -> void:
	var reg := _create_registry()
	reg.register(_create_unit(0, "military"))
	reg.register(_create_unit(1, "villager"))
	reg.register(_create_building(0, "barracks"))
	assert_int(reg.get_count()).is_equal(3)
	reg.clear()
	assert_int(reg.get_count()).is_equal(0)
	assert_int(reg.get_by_owner(0).size()).is_equal(0)
	assert_int(reg.get_by_category("military").size()).is_equal(0)


# --- category resolution ---


func test_entity_category_fallback() -> void:
	var reg := _create_registry()
	var unit := _create_unit(0, "", "wild_fauna")
	reg.register(unit)
	var result: Array[Node2D] = reg.get_by_category("wild_fauna")
	assert_int(result.size()).is_equal(1)


func test_unit_category_takes_priority_over_entity_category() -> void:
	var reg := _create_registry()
	var unit := _create_unit(0, "military", "some_other")
	reg.register(unit)
	# unit_category "military" should win over entity_category "some_other"
	assert_int(reg.get_by_category("military").size()).is_equal(1)
	assert_int(reg.get_by_category("some_other").size()).is_equal(0)


func test_entity_with_no_category_still_indexed_by_owner() -> void:
	var reg := _create_registry()
	var unit := _create_unit(0, "", "")
	reg.register(unit)
	assert_int(reg.get_by_owner(0).size()).is_equal(1)
	assert_int(reg.get_count()).is_equal(1)


# --- unregister cleans indices ---


func test_unregister_cleans_owner_index() -> void:
	var reg := _create_registry()
	var unit := _create_unit(0, "military")
	reg.register(unit)
	reg.unregister(unit)
	assert_int(reg.get_by_owner(0).size()).is_equal(0)


func test_unregister_cleans_category_index() -> void:
	var reg := _create_registry()
	var unit := _create_unit(0, "military")
	reg.register(unit)
	reg.unregister(unit)
	assert_int(reg.get_by_category("military").size()).is_equal(0)


func test_unregister_cleans_composite_index() -> void:
	var reg := _create_registry()
	var unit := _create_unit(0, "military")
	reg.register(unit)
	reg.unregister(unit)
	assert_int(reg.get_by_owner_and_category(0, "military").size()).is_equal(0)


# --- gaia / negative owner_id ---


func test_gaia_entities_indexed_by_negative_owner() -> void:
	var reg := _create_registry()
	var wolf := _create_unit(-1, "", "wild_fauna")
	reg.register(wolf)
	assert_int(reg.get_by_owner(-1).size()).is_equal(1)
	assert_int(reg.get_count_by_owner(-1)).is_equal(1)


# --- mixed types ---


func test_mixed_units_and_buildings() -> void:
	var reg := _create_registry()
	var unit := _create_unit(0, "military")
	var building := _create_building(0, "barracks")
	reg.register(unit)
	reg.register(building)
	assert_int(reg.get_count()).is_equal(2)
	assert_int(reg.get_by_owner(0).size()).is_equal(2)
	assert_int(reg.get_by_category("military").size()).is_equal(1)
	assert_int(reg.get_by_category("building").size()).is_equal(1)
	assert_int(reg.get_by_owner_and_category(0, "military").size()).is_equal(1)
	assert_int(reg.get_by_owner_and_category(0, "building").size()).is_equal(1)


# --- multiple factions scenario ---


func test_multi_faction_isolation() -> void:
	var reg := _create_registry()
	var p0_mil := _create_unit(0, "military")
	var p0_vil := _create_unit(0, "villager")
	var p1_mil := _create_unit(1, "military")
	var p1_bld := _create_building(1, "town_center")
	var gaia := _create_unit(-1, "", "wild_fauna")
	reg.register(p0_mil)
	reg.register(p0_vil)
	reg.register(p1_mil)
	reg.register(p1_bld)
	reg.register(gaia)
	assert_int(reg.get_count()).is_equal(5)
	assert_int(reg.get_count_by_owner(0)).is_equal(2)
	assert_int(reg.get_count_by_owner(1)).is_equal(2)
	assert_int(reg.get_count_by_owner(-1)).is_equal(1)
	assert_int(reg.get_by_owner_and_category(1, "military").size()).is_equal(1)
	assert_int(reg.get_by_owner_and_category(1, "building").size()).is_equal(1)
