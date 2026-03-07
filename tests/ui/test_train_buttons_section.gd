extends GdUnitTestSuite
## Tests for scripts/ui/train_buttons_section.gd — train button creation,
## hotkey handling, button state refresh, and tooltip generation.

const TrainScript := preload("res://scripts/ui/train_buttons_section.gd")


## Lightweight mock building: a Node2D with building_name, owner_id, and
## an optional child ProductionQueue stub.
class MockPQ:
	extends Node

	var _can_produce_result: bool = true
	var _queued: Array[String] = []

	func can_produce(_unit_type: String) -> bool:
		return _can_produce_result

	func add_to_queue(unit_type: String) -> bool:
		_queued.append(unit_type)
		return true


func _create_section() -> HBoxContainer:
	var section := HBoxContainer.new()
	section.set_script(TrainScript)
	add_child(section)
	return auto_free(section)


func _create_building(
	bname: String = "barracks",
	owner: int = 0,
	under_construction: bool = false,
	add_pq: bool = true,
) -> Node2D:
	var b := Node2D.new()
	b.set("building_name", bname)
	b.set("owner_id", owner)
	b.set("under_construction", under_construction)
	if add_pq:
		var pq := MockPQ.new()
		pq.name = "ProductionQueue"
		b.add_child(pq)
	add_child(b)
	return auto_free(b)


# -- Constants --


func test_train_hotkeys_length() -> void:
	var section := _create_section()
	assert_int(section.TRAIN_HOTKEYS.size()).is_equal(5)


func test_resource_name_to_type_has_five_entries() -> void:
	var section := _create_section()
	assert_int(section.RESOURCE_NAME_TO_TYPE.size()).is_equal(5)


# -- _ready defaults --


func test_starts_invisible() -> void:
	var section := _create_section()
	assert_bool(section.visible).is_false()


# -- update_for_building --


func test_update_null_building_hides() -> void:
	var section := _create_section()
	section.visible = true
	section.update_for_building(null)
	assert_bool(section.visible).is_false()


func test_update_under_construction_hides() -> void:
	var section := _create_section()
	var b := _create_building("barracks", 0, true)
	section.update_for_building(b)
	assert_bool(section.visible).is_false()


func test_update_enemy_building_hides() -> void:
	var section := _create_section()
	var b := _create_building("barracks", 1)
	section.update_for_building(b)
	assert_bool(section.visible).is_false()


func test_update_no_pq_hides() -> void:
	var section := _create_section()
	var b := _create_building("barracks", 0, false, false)
	section.update_for_building(b)
	assert_bool(section.visible).is_false()


# -- try_hotkey --


func test_try_hotkey_returns_false_when_invisible() -> void:
	var section := _create_section()
	section.visible = false
	assert_bool(section.try_hotkey("Q")).is_false()


func test_try_hotkey_returns_false_when_no_pq() -> void:
	var section := _create_section()
	section.visible = true
	assert_bool(section.try_hotkey("Q")).is_false()


func test_try_hotkey_unmatched_key_returns_false() -> void:
	var section := _create_section()
	section.visible = true
	section._production_queue = MockPQ.new()
	section._unit_types = ["infantry"]
	assert_bool(section.try_hotkey("Z")).is_false()


# -- refresh_button_states --


func test_refresh_no_pq_does_not_crash() -> void:
	var section := _create_section()
	section._production_queue = null
	section.refresh_button_states()
	# Should complete without error
	assert_bool(true).is_true()


func test_refresh_disables_when_cannot_produce() -> void:
	var section := _create_section()
	var pq := MockPQ.new()
	pq._can_produce_result = false
	section._production_queue = auto_free(pq)
	section._unit_types = ["infantry"]
	var btn := Button.new()
	section.add_child(btn)
	section._buttons.clear()
	section._buttons.append(btn)
	section.refresh_button_states()
	assert_bool(btn.disabled).is_true()


func test_refresh_enables_when_can_produce() -> void:
	var section := _create_section()
	var pq := MockPQ.new()
	pq._can_produce_result = true
	section._production_queue = auto_free(pq)
	section._unit_types = ["infantry"]
	var btn := Button.new()
	btn.disabled = true
	section.add_child(btn)
	section._buttons.clear()
	section._buttons.append(btn)
	section.refresh_button_states()
	assert_bool(btn.disabled).is_false()


# -- _build_tooltip --


func test_build_tooltip_empty_stats() -> void:
	var section := _create_section()
	var tip: String = section._build_tooltip("unknown_unit")
	assert_str(tip).is_equal("Unknown Unit")


# -- _create_train_button --


func test_create_train_button_with_hotkey() -> void:
	var section := _create_section()
	var btn: Button = section._create_train_button("infantry", "Q")
	auto_free(btn)
	assert_str(btn.text).is_equal("[Q] Infantry")
	assert_vector(btn.custom_minimum_size).is_equal(Vector2(80, 28))


func test_create_train_button_without_hotkey() -> void:
	var section := _create_section()
	var btn: Button = section._create_train_button("war_chariot", "")
	auto_free(btn)
	assert_str(btn.text).is_equal("War Chariot")


# -- _hide --


func test_hide_clears_state() -> void:
	var section := _create_section()
	section._building = Node2D.new()
	auto_free(section._building)
	section._production_queue = Node.new()
	auto_free(section._production_queue)
	section._unit_types = ["infantry"]
	section.visible = true
	section._hide()
	assert_bool(section.visible).is_false()
	assert_object(section._building).is_null()
	assert_object(section._production_queue).is_null()
	assert_array(section._unit_types).is_empty()
