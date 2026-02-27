extends GdUnitTestSuite
## Tests for transport embark/disembark system.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const TransportHandlerScript := preload("res://scripts/prototype/transport_handler.gd")

var _mock_land_script: GDScript
var _mock_water_script: GDScript


func before() -> void:
	_mock_land_script = GDScript.new()
	_mock_land_script.source_code = (
		"extends Node2D\n"
		+ "var owner_id: int = 0\n"
		+ "var hp: int = 50\n"
		+ "var max_hp: int = 50\n"
		+ "var _is_dead: bool = false\n"
		+ 'var unit_type: String = "militia"\n'
		+ "var stats: RefCounted = null\n"
		+ "func _die() -> void:\n"
		+ "\t_is_dead = true\n"
	)
	_mock_land_script.reload()
	_mock_water_script = GDScript.new()
	_mock_water_script.source_code = (
		"extends Node2D\n"
		+ "var owner_id: int = 0\n"
		+ "var hp: int = 50\n"
		+ "var max_hp: int = 50\n"
		+ "var _is_dead: bool = false\n"
		+ 'var unit_type: String = "warship"\n'
		+ 'var movement_type: String = "water"\n'
		+ "var stats: RefCounted = null\n"
		+ "func _die() -> void:\n"
		+ "\t_is_dead = true\n"
	)
	_mock_water_script.reload()


func _create_transport(capacity: int = 10) -> Node2D:
	var t := Node2D.new()
	t.set_script(UnitScript)
	t.unit_type = "transport_ship"
	t.owner_id = 0
	add_child(t)
	auto_free(t)
	# Override after _ready() to avoid DataLoader dependency
	t._transport_capacity = capacity
	t._transport = TransportHandlerScript.new()
	t._transport.capacity = capacity
	t._transport.config = {
		"load_time_per_unit": 1.5,
		"unload_time_per_unit": 1.0,
		"shallows_search_radius": 3,
		"unload_spread_radius_tiles": 2,
	}
	t._combat_config = {"show_damage_numbers": false}
	return t


func _create_land_unit() -> Node2D:
	var u := Node2D.new()
	u.set_script(_mock_land_script)
	u.owner_id = 0
	add_child(u)
	auto_free(u)
	return u


func _create_water_unit() -> Node2D:
	var u := Node2D.new()
	u.set_script(_mock_water_script)
	u.owner_id = 0
	add_child(u)
	auto_free(u)
	return u


func test_embark_unit_hides_and_disables() -> void:
	var t := _create_transport()
	var u := _create_land_unit()
	var result: bool = t.embark_unit(u)
	assert_bool(result).is_true()
	t._transport.tick(1.5, false)
	assert_bool(u.visible).is_false()
	assert_bool(u.is_processing()).is_false()
	assert_int(t._transport.embarked_units.size()).is_equal(1)


func test_embark_respects_capacity() -> void:
	var t := _create_transport(2)
	var u1 := _create_land_unit()
	var u2 := _create_land_unit()
	var u3 := _create_land_unit()
	assert_bool(t.embark_unit(u1)).is_true()
	assert_bool(t.embark_unit(u2)).is_true()
	assert_bool(t.embark_unit(u3)).is_false()


func test_embark_rejects_water_units() -> void:
	var t := _create_transport()
	var u := _create_water_unit()
	var result: bool = t.embark_unit(u)
	assert_bool(result).is_false()


func test_can_embark_false_when_full() -> void:
	var t := _create_transport(1)
	assert_bool(t.can_embark()).is_true()
	var u := _create_land_unit()
	t.embark_unit(u)
	assert_bool(t.can_embark()).is_false()


func test_embarked_count_includes_queue() -> void:
	var t := _create_transport()
	var u1 := _create_land_unit()
	var u2 := _create_land_unit()
	t.embark_unit(u1)
	t.embark_unit(u2)
	assert_int(t.get_embarked_count()).is_equal(2)


func test_load_timer_delays_boarding() -> void:
	var t := _create_transport()
	var u := _create_land_unit()
	t.embark_unit(u)
	t._transport.tick(1.0, false)
	assert_int(t._transport.load_queue.size()).is_equal(1)
	assert_int(t._transport.embarked_units.size()).is_equal(0)
	t._transport.tick(0.6, false)
	assert_int(t._transport.load_queue.size()).is_equal(0)
	assert_int(t._transport.embarked_units.size()).is_equal(1)


func test_disembark_shows_and_enables() -> void:
	var t := _create_transport()
	var u := _create_land_unit()
	t.embark_unit(u)
	t._transport.tick(1.5, false)
	assert_bool(u.visible).is_false()
	t.disembark_all(Vector2(300, 300))
	t._moving = false
	t._transport.tick(1.0, false)
	assert_bool(u.visible).is_true()
	assert_bool(u.is_processing()).is_true()


func test_disembark_clears_embarked_list() -> void:
	var t := _create_transport()
	var u1 := _create_land_unit()
	var u2 := _create_land_unit()
	t.embark_unit(u1)
	t.embark_unit(u2)
	t._transport.tick(1.5, false)
	t._transport.tick(1.5, false)
	assert_int(t._transport.embarked_units.size()).is_equal(2)
	t.disembark_all(Vector2(200, 200))
	t._moving = false
	t._transport.tick(1.0, false)
	t._transport.tick(1.0, false)
	assert_int(t.get_embarked_count()).is_equal(0)
	assert_bool(t._transport.is_unloading).is_false()


func test_disembark_positions_around_shore() -> void:
	var t := _create_transport()
	t.global_position = Vector2(100, 100)
	var u := _create_land_unit()
	t.embark_unit(u)
	t._transport.tick(1.5, false)
	var shore := Vector2(400, 400)
	t.disembark_all(shore)
	t._moving = false
	t._transport.tick(1.0, false)
	var dist := u.global_position.distance_to(shore)
	assert_float(dist).is_less_equal(129.0)


func test_transport_death_kills_passengers() -> void:
	var t := _create_transport()
	var u1 := _create_land_unit()
	var u2 := _create_land_unit()
	t.embark_unit(u1)
	t.embark_unit(u2)
	t._transport.tick(1.5, false)
	t._transport.tick(1.5, false)
	t._transport.kill_passengers()
	assert_int(u1.hp).is_equal(0)
	assert_bool(u1._is_dead).is_true()
	assert_int(u2.hp).is_equal(0)
	assert_bool(u2._is_dead).is_true()
	assert_int(t._transport.embarked_units.size()).is_equal(0)


func test_save_load_round_trip() -> void:
	var t := _create_transport()
	var u := _create_land_unit()
	u.name = "test_passenger"
	t.embark_unit(u)
	t._transport.tick(1.5, false)
	var state: Dictionary = t.save_state()
	assert_bool(state.has("embarked_unit_names")).is_true()
	var names: Array = state["embarked_unit_names"]
	assert_int(names.size()).is_equal(1)
	assert_str(names[0]).is_equal("test_passenger")
	var t2 := _create_transport()
	t2.load_state(state)
	assert_int(t2._transport.pending_names.size()).is_equal(1)
	assert_str(t2._transport.pending_names[0]).is_equal("test_passenger")


func test_entity_category_own_transport() -> void:
	var t := _create_transport()
	t.entity_category = ""
	assert_str(t.get_entity_category()).is_equal("own_transport")


func test_entity_category_enemy_transport_is_enemy() -> void:
	var t := _create_transport()
	t.owner_id = 1
	t.entity_category = ""
	assert_str(t.get_entity_category()).is_equal("enemy_unit")


func test_embark_command_resolved_from_table() -> void:
	var table: Dictionary = {
		"default": {"own_transport": "embark"},
	}
	var result: String = CommandResolver.resolve("militia", "own_transport", table)
	assert_str(result).is_equal("embark")
