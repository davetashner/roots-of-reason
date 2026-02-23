extends GdUnitTestSuite
## Tests for CommandResolver — pure-function command resolution logic.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")

var _table: Dictionary = {
	"default":
	{
		"enemy_unit": "attack",
		"enemy_building": "attack",
		"own_building": "garrison",
		"resource_node": "move",
	},
	"villager":
	{
		"enemy_unit": "attack",
		"enemy_building": "attack",
		"own_building": "garrison",
		"resource_node": "gather",
	},
}


func _make_unit(type: String = "land", uid: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = type
	unit.owner_id = uid
	return auto_free(unit)


func _make_target_stub(category: String) -> Node:
	var node := Node.new()
	node.set_meta("_entity_category", category)
	node.set_script(load("res://tests/prototype/helpers/stub_entity.gd"))
	node.entity_category = category
	return auto_free(node)


# -- resolve() --


func test_resolve_villager_resource_returns_gather() -> void:
	var cmd := CommandResolver.resolve("villager", "resource_node", _table)
	assert_str(cmd).is_equal("gather")


func test_resolve_villager_enemy_returns_attack() -> void:
	var cmd := CommandResolver.resolve("villager", "enemy_unit", _table)
	assert_str(cmd).is_equal("attack")


func test_resolve_infantry_enemy_returns_attack() -> void:
	var cmd := CommandResolver.resolve("infantry", "enemy_unit", _table)
	assert_str(cmd).is_equal("attack")


func test_resolve_infantry_resource_returns_move() -> void:
	var cmd := CommandResolver.resolve("infantry", "resource_node", _table)
	assert_str(cmd).is_equal("move")


func test_resolve_any_own_building_returns_garrison() -> void:
	var cmd := CommandResolver.resolve("default", "own_building", _table)
	assert_str(cmd).is_equal("garrison")


func test_resolve_ground_returns_move() -> void:
	var cmd := CommandResolver.resolve("villager", "ground", _table)
	assert_str(cmd).is_equal("move")


func test_resolve_unknown_unit_uses_default() -> void:
	var cmd := CommandResolver.resolve("catapult", "enemy_building", _table)
	assert_str(cmd).is_equal("attack")


func test_resolve_empty_table_returns_move() -> void:
	var cmd := CommandResolver.resolve("villager", "resource_node", {})
	assert_str(cmd).is_equal("move")


# -- get_primary_unit_type() --


func test_get_primary_unit_type_homogeneous() -> void:
	var u1 := _make_unit("villager")
	var u2 := _make_unit("villager")
	var result := CommandResolver.get_primary_unit_type([u1, u2])
	assert_str(result).is_equal("villager")


func test_get_primary_unit_type_mixed() -> void:
	var u1 := _make_unit("villager")
	var u2 := _make_unit("infantry")
	var result := CommandResolver.get_primary_unit_type([u1, u2])
	assert_str(result).is_equal("default")


func test_get_primary_unit_type_empty() -> void:
	var result := CommandResolver.get_primary_unit_type([])
	assert_str(result).is_equal("default")


# -- get_target_category() --


func test_get_target_category_enemy_unit() -> void:
	var unit := _make_unit("land", 1)
	var result := CommandResolver.get_target_category(unit)
	assert_str(result).is_equal("enemy_unit")


func test_get_target_category_resource_node() -> void:
	var target := _make_target_stub("resource_node")
	var result := CommandResolver.get_target_category(target)
	assert_str(result).is_equal("resource_node")


func test_get_target_category_null() -> void:
	var result := CommandResolver.get_target_category(null)
	assert_str(result).is_equal("ground")
