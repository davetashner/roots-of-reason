extends GdUnitTestSuite
## Tests for prototype_resource_node.gd — yield math, depletion, save/load.

const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")


func _create_node(res_type: String = "food", yield_amt: int = 100) -> Node2D:
	var n := Node2D.new()
	n.set_script(ResourceNodeScript)
	n.resource_name = "berry_bush"
	n.resource_type = res_type
	n.total_yield = yield_amt
	n.current_yield = yield_amt
	add_child(n)
	auto_free(n)
	return n


# -- apply_gather_work --


func test_apply_gather_work_reduces_yield() -> void:
	var n := _create_node("food", 100)
	var gathered: int = n.apply_gather_work(5.0)
	assert_int(gathered).is_equal(5)
	assert_int(n.current_yield).is_equal(95)


func test_apply_gather_work_clamps_to_remaining() -> void:
	var n := _create_node("food", 3)
	var gathered: int = n.apply_gather_work(10.0)
	assert_int(gathered).is_equal(3)
	assert_int(n.current_yield).is_equal(0)


func test_apply_gather_work_returns_zero_when_depleted() -> void:
	var n := _create_node("food", 0)
	var gathered: int = n.apply_gather_work(5.0)
	assert_int(gathered).is_equal(0)


func test_apply_gather_work_emits_depleted() -> void:
	var n := _create_node("food", 5)
	var monitor := monitor_signals(n)
	n.apply_gather_work(5.0)
	await assert_signal(monitor).is_emitted("depleted", [n])


func test_apply_gather_work_no_signal_when_not_empty() -> void:
	var n := _create_node("food", 10)
	var monitor := monitor_signals(n)
	n.apply_gather_work(3.0)
	await assert_signal(monitor).is_not_emitted("depleted")


func test_apply_gather_work_truncates_float() -> void:
	var n := _create_node("food", 100)
	# 2.9 truncates to 2
	var gathered: int = n.apply_gather_work(2.9)
	assert_int(gathered).is_equal(2)
	assert_int(n.current_yield).is_equal(98)


# -- save_state / load_state --


func test_save_state_includes_all_fields() -> void:
	var n := _create_node("food", 100)
	n.position = Vector2(50, 75)
	n.apply_gather_work(10.0)
	var state: Dictionary = n.save_state()
	assert_str(state["resource_name"]).is_equal("berry_bush")
	assert_str(state["resource_type"]).is_equal("food")
	assert_int(int(state["total_yield"])).is_equal(100)
	assert_int(int(state["current_yield"])).is_equal(90)
	assert_float(float(state["position_x"])).is_equal_approx(50.0, 0.01)
	assert_float(float(state["position_y"])).is_equal_approx(75.0, 0.01)


func test_save_load_round_trip() -> void:
	var n := _create_node("wood", 200)
	n.resource_name = "tree"
	n.position = Vector2(30, 40)
	n.apply_gather_work(50.0)
	var state: Dictionary = n.save_state()
	var n2 := _create_node()
	n2.load_state(state)
	assert_str(n2.resource_name).is_equal("tree")
	assert_str(n2.resource_type).is_equal("wood")
	assert_int(n2.total_yield).is_equal(200)
	assert_int(n2.current_yield).is_equal(150)
	assert_float(n2.position.x).is_equal_approx(30.0, 0.01)
	assert_float(n2.position.y).is_equal_approx(40.0, 0.01)
