extends GdUnitTestSuite
## Tests for command_panel.gd — context-sensitive command button grid with
## dynamic villager build menu.

const CommandPanelScript := preload("res://scripts/ui/command_panel.gd")

var _original_age: int = 0


func before() -> void:
	_original_age = GameManager.current_age


func after() -> void:
	GameManager.current_age = _original_age


class StubUnit:
	extends Node2D
	var selected: bool = false
	var unit_type: String = "villager"
	var building_name: String = ""
	var owner_id: int = 0

	func select() -> void:
		selected = true

	func deselect() -> void:
		selected = false

	func stop() -> void:
		pass

	func hold_position() -> void:
		pass


class StubInputHandler:
	extends Node
	var _selected: Array[Node] = []

	func _get_selected_units() -> Array[Node]:
		return _selected


class StubBuildingPlacer:
	extends Node
	var last_building: String = ""
	var last_player_id: int = -1
	## Tracks which buildings are "unlocked" for testing
	var _unlocked: Dictionary = {}

	func start_placement(building_name: String, player_id: int) -> bool:
		last_building = building_name
		last_player_id = player_id
		return true

	func is_active() -> bool:
		return false

	func is_building_unlocked(building_name: String, _player_id: int) -> bool:
		if _unlocked.is_empty():
			return true
		return _unlocked.has(building_name)

	func get_building_cost_multiplier() -> float:
		return 1.0


func _create_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "CommandPanelWidget"
	panel.set_script(CommandPanelScript)
	add_child(panel)
	auto_free(panel)
	return panel


# -- Villager dynamic build menu --


func test_villager_selection_shows_tab_bar() -> void:
	var panel := _create_panel()
	var unit := StubUnit.new()
	unit.unit_type = "villager"
	add_child(unit)
	auto_free(unit)
	panel.update_commands([unit])
	assert_bool(panel._tab_bar.visible).is_true()
	assert_bool(panel._is_villager_mode).is_true()


func test_non_villager_selection_hides_tab_bar() -> void:
	var panel := _create_panel()
	var unit := StubUnit.new()
	unit.unit_type = "infantry"
	add_child(unit)
	auto_free(unit)
	panel.update_commands([unit])
	assert_bool(panel._tab_bar.visible).is_false()
	assert_bool(panel._is_villager_mode).is_false()


func test_dynamic_build_menu_shows_unlocked_civilian_buildings() -> void:
	var panel := _create_panel()
	var placer := StubBuildingPlacer.new()
	placer._unlocked = {"house": true, "farm": true, "town_center": true}
	add_child(placer)
	auto_free(placer)
	var handler := StubInputHandler.new()
	add_child(handler)
	auto_free(handler)
	panel.setup(handler, placer)
	panel._build_tab = "civilian"
	GameManager.current_age = 0
	var unit := StubUnit.new()
	unit.unit_type = "villager"
	add_child(unit)
	auto_free(unit)
	panel.update_commands([unit])
	# Should have buttons in the grid
	var grid: GridContainer = panel._grid
	assert_that(grid.get_child_count()).is_greater(0)
	# Check that at least one button has a build action
	var found_build := false
	for child in grid.get_children():
		if child is Button and child.has_meta("command"):
			var cmd: Dictionary = child.get_meta("command")
			if cmd.get("action", "") == "build":
				found_build = true
				break
	assert_bool(found_build).is_true()


func test_dynamic_build_menu_filters_locked_buildings() -> void:
	var panel := _create_panel()
	var placer := StubBuildingPlacer.new()
	# Only house is unlocked — barracks, market etc should be hidden
	placer._unlocked = {"house": true, "farm": true}
	add_child(placer)
	auto_free(placer)
	var handler := StubInputHandler.new()
	add_child(handler)
	auto_free(handler)
	panel.setup(handler, placer)
	panel._build_tab = "military"
	var unit := StubUnit.new()
	unit.unit_type = "villager"
	add_child(unit)
	auto_free(unit)
	panel.update_commands([unit])
	# Military tab should have zero buttons since none unlocked
	assert_that(panel._grid.get_child_count()).is_equal(0)


func test_tab_switching_re_renders_grid() -> void:
	var panel := _create_panel()
	var placer := StubBuildingPlacer.new()
	add_child(placer)
	auto_free(placer)
	var handler := StubInputHandler.new()
	add_child(handler)
	auto_free(handler)
	panel.setup(handler, placer)
	var unit := StubUnit.new()
	unit.unit_type = "villager"
	add_child(unit)
	auto_free(unit)
	panel.update_commands([unit])
	# Switch to military tab
	panel._on_tab_pressed("military")
	assert_str(panel._build_tab).is_equal("military")


func test_default_tab_is_civilian() -> void:
	var panel := _create_panel()
	assert_str(panel._build_tab).is_equal("civilian")


# -- Non-villager commands still work --


func test_get_commands_for_empty_selection_returns_empty() -> void:
	var panel := _create_panel()
	var commands: Array = panel._get_commands_for_selection([])
	assert_that(commands.size()).is_equal(0)


func test_check_affordability_with_resources_returns_true() -> void:
	var panel := _create_panel()
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 0,
				ResourceManager.ResourceType.WOOD: 200,
				ResourceManager.ResourceType.STONE: 200,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var command := {"id": "build_house", "action": "build", "building": "house"}
	var result: bool = panel._check_affordability(command)
	assert_that(result).is_true()


func test_check_affordability_without_resources_returns_false() -> void:
	var panel := _create_panel()
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 0,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var command := {"id": "build_house", "action": "build", "building": "house"}
	var result: bool = panel._check_affordability(command)
	assert_that(result).is_false()


func test_get_commands_for_default_unit_returns_stop_hold() -> void:
	var panel := _create_panel()
	var unit := StubUnit.new()
	unit.unit_type = "infantry"
	unit.selected = true
	add_child(unit)
	auto_free(unit)
	var commands: Array = panel._get_commands_for_selection([unit])
	assert_that(commands.size()).is_greater(0)
	var ids: Array[String] = []
	for cmd: Dictionary in commands:
		ids.append(cmd.get("id", ""))
	assert_that(ids).contains(["stop"])
	assert_that(ids).contains(["hold"])


func test_update_commands_creates_buttons() -> void:
	var panel := _create_panel()
	var placer := StubBuildingPlacer.new()
	add_child(placer)
	auto_free(placer)
	var handler := StubInputHandler.new()
	add_child(handler)
	auto_free(handler)
	panel.setup(handler, placer)
	var unit := StubUnit.new()
	unit.unit_type = "villager"
	unit.selected = true
	add_child(unit)
	auto_free(unit)
	panel.update_commands([unit])
	var grid: GridContainer = panel._grid
	assert_that(grid.get_child_count()).is_greater(0)


func test_update_commands_clears_on_empty_selection() -> void:
	var panel := _create_panel()
	var placer := StubBuildingPlacer.new()
	add_child(placer)
	auto_free(placer)
	var handler := StubInputHandler.new()
	add_child(handler)
	auto_free(handler)
	panel.setup(handler, placer)
	# First populate with commands
	var unit := StubUnit.new()
	unit.unit_type = "villager"
	add_child(unit)
	auto_free(unit)
	panel.update_commands([unit])
	# Then clear
	panel.update_commands([])
	var commands: Array = panel._get_commands_for_selection([])
	assert_that(commands.size()).is_equal(0)


func test_build_command_calls_building_placer() -> void:
	var panel := _create_panel()
	var placer := StubBuildingPlacer.new()
	add_child(placer)
	auto_free(placer)
	var handler := StubInputHandler.new()
	add_child(handler)
	auto_free(handler)
	panel.setup(handler, placer)
	var command := {"id": "build_house", "action": "build", "building": "house"}
	panel._on_command_pressed(command)
	assert_that(placer.last_building).is_equal("house")
	assert_that(placer.last_player_id).is_equal(0)


func test_non_build_action_affordability_returns_true() -> void:
	var panel := _create_panel()
	var command := {"id": "stop", "action": "stop"}
	var result: bool = panel._check_affordability(command)
	assert_that(result).is_true()


func test_save_load_state_includes_build_tab() -> void:
	var panel := _create_panel()
	panel._player_id = 2
	panel._build_tab = "military"
	var state: Dictionary = panel.save_state()
	assert_that(state.get("player_id")).is_equal(2)
	assert_that(state.get("build_tab")).is_equal("military")
	panel._player_id = 0
	panel._build_tab = "civilian"
	panel.load_state(state)
	assert_that(panel._player_id).is_equal(2)
	assert_that(panel._build_tab).is_equal("military")


func test_building_name_lookup_returns_market_commands() -> void:
	var panel := _create_panel()
	var unit := StubUnit.new()
	unit.building_name = "market"
	unit.selected = true
	add_child(unit)
	auto_free(unit)
	var commands: Array = panel._get_commands_for_selection([unit])
	assert_that(commands.size()).is_greater(0)
	var ids: Array[String] = []
	for cmd: Dictionary in commands:
		ids.append(cmd.get("id", ""))
	assert_that(ids).contains(["sell_food"])


class StubTradeManager:
	extends Node
	var last_sell_resource: String = ""
	var last_sell_amount: int = 0
	var last_player_id: int = -1

	func execute_exchange(player_id: int, sell_resource: String, amount: int) -> bool:
		last_player_id = player_id
		last_sell_resource = sell_resource
		last_sell_amount = amount
		return true


func test_trade_action_fires_execute_exchange() -> void:
	var panel := _create_panel()
	var tm := StubTradeManager.new()
	add_child(tm)
	auto_free(tm)
	var handler := StubInputHandler.new()
	add_child(handler)
	auto_free(handler)
	var placer := StubBuildingPlacer.new()
	add_child(placer)
	auto_free(placer)
	panel.setup(handler, placer, tm)
	var command := {
		"id": "sell_food",
		"action": "trade",
		"sell_resource": "food",
		"sell_amount": 100,
	}
	panel._on_command_pressed(command)
	assert_that(tm.last_sell_resource).is_equal("food")
	assert_that(tm.last_sell_amount).is_equal(100)


func test_trade_affordability_with_resources_returns_true() -> void:
	var panel := _create_panel()
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 200,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var command := {
		"id": "sell_food",
		"action": "trade",
		"sell_resource": "food",
		"sell_amount": 100,
	}
	var result: bool = panel._check_affordability(command)
	assert_that(result).is_true()


func test_get_commands_for_town_center_returns_produce_villager() -> void:
	var panel := _create_panel()
	var unit := StubUnit.new()
	unit.building_name = "town_center"
	unit.selected = true
	add_child(unit)
	auto_free(unit)
	var commands: Array = panel._get_commands_for_selection([unit])
	assert_that(commands.size()).is_greater(0)
	var ids: Array[String] = []
	for cmd: Dictionary in commands:
		ids.append(cmd.get("id", ""))
	assert_that(ids).contains(["produce_villager"])


class StubProductionQueue:
	extends Node
	var last_unit_type: String = ""
	var queue_count: int = 0

	func add_to_queue(unit_type: String) -> bool:
		last_unit_type = unit_type
		queue_count += 1
		return true


func test_produce_action_calls_add_to_queue() -> void:
	var panel := _create_panel()
	var handler := StubInputHandler.new()
	add_child(handler)
	auto_free(handler)
	var placer := StubBuildingPlacer.new()
	add_child(placer)
	auto_free(placer)
	# Create a building with a ProductionQueue child
	var building := StubUnit.new()
	building.building_name = "town_center"
	add_child(building)
	auto_free(building)
	var pq := StubProductionQueue.new()
	pq.name = "ProductionQueue"
	building.add_child(pq)
	handler._selected = [building]
	panel.setup(handler, placer)
	var command := {"id": "produce_villager", "action": "produce", "unit": "villager"}
	panel._on_command_pressed(command)
	assert_that(pq.last_unit_type).is_equal("villager")


func test_produce_affordability_with_food_returns_true() -> void:
	var panel := _create_panel()
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 100,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var command := {"id": "produce_villager", "action": "produce", "unit": "villager"}
	var result: bool = panel._check_affordability(command)
	assert_that(result).is_true()


func test_produce_affordability_insufficient_returns_false() -> void:
	var panel := _create_panel()
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 10,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var command := {"id": "produce_villager", "action": "produce", "unit": "villager"}
	var result: bool = panel._check_affordability(command)
	assert_that(result).is_false()


func test_trade_affordability_insufficient_returns_false() -> void:
	var panel := _create_panel()
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 50,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var command := {
		"id": "sell_food",
		"action": "trade",
		"sell_resource": "food",
		"sell_amount": 100,
	}
	var result: bool = panel._check_affordability(command)
	assert_that(result).is_false()
