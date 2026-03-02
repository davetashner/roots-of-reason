extends GdUnitTestSuite
## Tests for production queue display in info_panel.gd — queue icons,
## progress bar, cancel/refund, and estimated completion time.

const InfoPanelScript := preload("res://scripts/ui/info_panel.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const ProductionQueueScript := preload("res://scripts/prototype/production_queue.gd")


func _create_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_script(InfoPanelScript)
	add_child(panel)
	auto_free(panel)
	return panel


func _create_building(bname: String = "barracks") -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = bname
	b.max_hp = 1200
	b.hp = 1200
	b.under_construction = false
	b.build_progress = 1.0
	b.footprint = Vector2i(3, 3)
	b.grid_pos = Vector2i(5, 5)
	b.owner_id = 0
	add_child(b)
	auto_free(b)
	return b


func _create_production_queue(building: Node2D) -> Node:
	var pq := Node.new()
	pq.set_script(ProductionQueueScript)
	pq.name = "ProductionQueue"
	building.add_child(pq)
	pq.setup(building, 0)
	return pq


class StubProductionQueue:
	extends Node
	## Lightweight stub that exposes the same interface as ProductionQueue
	## without needing DataLoader or ResourceManager.

	signal queue_changed(building: Node2D)

	var _queue: Array[String] = []
	var _progress_ratio: float = 0.0
	var _current_train_time: float = 25.0
	var _elapsed: float = 0.0
	var _max_queue_size: int = 5
	var _train_times: Dictionary = {}
	var _cancel_log: Array[int] = []

	func get_queue() -> Array[String]:
		return _queue.duplicate()

	func get_progress() -> float:
		return _progress_ratio

	func get_current_train_time() -> float:
		return _current_train_time

	func get_elapsed_time() -> float:
		return _elapsed

	func get_max_queue_size() -> int:
		return _max_queue_size

	func get_train_time_for(unit_type: String) -> float:
		return float(_train_times.get(unit_type, 25.0))

	func cancel_at(index: int) -> void:
		_cancel_log.append(index)
		if index >= 0 and index < _queue.size():
			_queue.remove_at(index)
		queue_changed.emit(null)

	func add_to_queue(unit_type: String) -> bool:
		if _queue.size() >= _max_queue_size:
			return false
		_queue.append(unit_type)
		return true


func _create_stub_queue(building: Node2D) -> StubProductionQueue:
	var pq := StubProductionQueue.new()
	pq.name = "ProductionQueue"
	building.add_child(pq)
	return pq


# -- Queue section visibility --


func test_queue_section_hidden_when_no_production_queue() -> void:
	var panel := _create_panel()
	var b := _create_building("house")
	# House has no ProductionQueue child
	panel.show_building(b)
	assert_bool(panel._queue_section.visible).is_false()


func test_queue_section_hidden_when_queue_empty() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = []
	panel.show_building(b)
	assert_bool(panel._queue_section.visible).is_false()


func test_queue_section_visible_when_queue_has_items() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry"]
	panel.show_building(b)
	assert_bool(panel._queue_section.visible).is_true()


# -- Queue icons --


func test_queue_3_infantry_shows_3_icons() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry", "infantry", "infantry"]
	panel.show_building(b)
	var icon_count: int = panel._queue_icons_container.get_child_count()
	assert_int(icon_count).is_equal(3)


func test_queue_icons_show_unit_type_abbreviation() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry", "archer"]
	panel.show_building(b)
	var first_btn: Button = panel._queue_icons_container.get_child(0) as Button
	assert_str(first_btn.text).is_equal("IN")
	var second_btn: Button = panel._queue_icons_container.get_child(1) as Button
	assert_str(second_btn.text).is_equal("AR")


func test_queue_icons_tooltip_shows_training_for_first() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry", "archer"]
	panel.show_building(b)
	var first_btn: Button = panel._queue_icons_container.get_child(0) as Button
	assert_str(first_btn.tooltip_text).contains("training")


func test_queue_icons_tooltip_shows_cancel_for_queued() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry", "archer"]
	panel.show_building(b)
	var second_btn: Button = panel._queue_icons_container.get_child(1) as Button
	assert_str(second_btn.tooltip_text).contains("cancel")


# -- Progress bar --


func test_progress_bar_shows_percentage() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry"]
	pq._progress_ratio = 0.5
	panel.show_building(b)
	assert_float(panel._queue_progress_bar.value).is_equal_approx(50.0, 0.1)


func test_progress_bar_zero_for_new_item() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry"]
	pq._progress_ratio = 0.0
	panel.show_building(b)
	assert_float(panel._queue_progress_bar.value).is_equal_approx(0.0, 0.1)


# -- Current training label --


func test_current_training_label_shows_unit_name() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry"]
	panel.show_building(b)
	assert_str(panel._queue_current_label.text).is_equal("Infantry")


func test_current_training_label_capitalizes_multi_word() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["war_elephant"]
	panel.show_building(b)
	assert_str(panel._queue_current_label.text).is_equal("War Elephant")


# -- Cancel --


func test_cancel_queued_unit_calls_cancel_at() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry", "archer", "cavalry"]
	panel.show_building(b)
	# Simulate pressing cancel on index 1 (second queued item)
	panel._on_queue_icon_pressed(pq, 1)
	assert_int(pq._cancel_log.size()).is_equal(1)
	assert_int(pq._cancel_log[0]).is_equal(1)


func test_cancel_queued_unit_removes_from_queue() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry", "archer", "cavalry"]
	panel.show_building(b)
	panel._on_queue_icon_pressed(pq, 1)
	# After cancel, archer removed — queue should be infantry, cavalry
	var remaining: Array[String] = pq.get_queue()
	assert_int(remaining.size()).is_equal(2)
	assert_str(remaining[0]).is_equal("infantry")
	assert_str(remaining[1]).is_equal("cavalry")


func test_cancel_with_real_queue_refunds_resources() -> void:
	## Integration: uses real ProductionQueue + ResourceManager to verify refund.
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 500,
				ResourceManager.ResourceType.WOOD: 500,
				ResourceManager.ResourceType.STONE: 500,
				ResourceManager.ResourceType.GOLD: 500,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_production_queue(b)
	# Queue an infantry (costs food:60 gold:20 per data)
	var food_before: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	var gold_before: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.GOLD)
	var added: bool = pq.add_to_queue("infantry")
	if not added:
		# If DataLoader isn't available, skip gracefully
		return
	var food_after_add: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	# Resources should have decreased
	assert_int(food_after_add).is_less(food_before)
	# Cancel the queued infantry
	pq.cancel_at(0)
	var food_after_cancel: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	# Resources should be restored
	assert_int(food_after_cancel).is_equal(food_before)


# -- ETA --


func test_eta_label_shows_remaining_time() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry"]
	pq._current_train_time = 25.0
	pq._elapsed = 10.0
	panel.show_building(b)
	# Remaining = 25 - 10 = 15 seconds
	assert_str(panel._queue_eta_label.text).is_equal("ETA: 15s")


func test_eta_label_includes_queued_items() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry", "infantry"]
	pq._current_train_time = 25.0
	pq._elapsed = 5.0
	pq._train_times = {"infantry": 25.0}
	panel.show_building(b)
	# Remaining current: 20s + queued: 25s = 45s
	assert_str(panel._queue_eta_label.text).is_equal("ETA: 45s")


func test_eta_label_empty_when_queue_empty() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = []
	panel.show_building(b)
	assert_str(panel._queue_eta_label.text).is_equal("")


# -- Panel height adjustment --


func test_panel_expands_when_queue_shown() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry"]
	panel.show_building(b)
	assert_float(panel.custom_minimum_size.y).is_equal(180.0)


func test_panel_shrinks_when_queue_hidden() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry"]
	panel.show_building(b)
	assert_float(panel.custom_minimum_size.y).is_equal(180.0)
	# Now show building without queue
	pq._queue = []
	panel.show_building(b)
	assert_float(panel.custom_minimum_size.y).is_equal(120.0)


# -- Queue hidden for non-buildings --


func test_queue_hidden_when_showing_unit() -> void:
	var panel := _create_panel()
	# First show building with queue
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry"]
	panel.show_building(b)
	assert_bool(panel._queue_section.visible).is_true()
	# Now show a unit — queue should hide
	var unit := Node2D.new()
	unit.set_meta("unit_type", "villager")
	add_child(unit)
	auto_free(unit)
	panel.show_unit(unit)
	assert_bool(panel._queue_section.visible).is_false()


func test_queue_hidden_on_clear() -> void:
	var panel := _create_panel()
	var b := _create_building()
	var pq := _create_stub_queue(b)
	pq._queue = ["infantry"]
	panel.show_building(b)
	assert_bool(panel._queue_section.visible).is_true()
	panel.clear()
	assert_bool(panel._queue_section.visible).is_false()
