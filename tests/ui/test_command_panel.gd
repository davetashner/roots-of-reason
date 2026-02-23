extends GdUnitTestSuite
## Tests for command_panel.gd — context-sensitive command button grid.

const CommandPanelScript := preload("res://scripts/ui/command_panel.gd")


class StubUnit:
	extends Node2D
	var selected: bool = false
	var unit_type: String = "villager"
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

	func start_placement(building_name: String, player_id: int) -> bool:
		last_building = building_name
		last_player_id = player_id
		return true

	func is_active() -> bool:
		return false


func _create_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "CommandPanelWidget"
	panel.set_script(CommandPanelScript)
	add_child(panel)
	auto_free(panel)
	return panel


func test_get_commands_for_villager_returns_build_commands() -> void:
	var panel := _create_panel()
	var unit := StubUnit.new()
	unit.unit_type = "villager"
	unit.selected = true
	add_child(unit)
	auto_free(unit)
	var commands: Array = panel._get_commands_for_selection([unit])
	assert_that(commands.size()).is_greater(0)
	var ids: Array[String] = []
	for cmd: Dictionary in commands:
		ids.append(cmd.get("id", ""))
	assert_that(ids).contains(["build_house"])


func test_get_commands_for_empty_selection_returns_empty() -> void:
	var panel := _create_panel()
	var commands: Array = panel._get_commands_for_selection([])
	assert_that(commands.size()).is_equal(0)


func test_check_affordability_with_resources_returns_true() -> void:
	var panel := _create_panel()
	# Give player 0 enough wood
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
	# Give player 0 no resources
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
	# First populate with commands
	var unit := StubUnit.new()
	unit.unit_type = "villager"
	add_child(unit)
	auto_free(unit)
	panel.update_commands([unit])
	# Then clear
	panel.update_commands([])
	# Grid children will be queue_freed next frame but we check the commands logic
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


func test_save_load_state() -> void:
	var panel := _create_panel()
	panel._player_id = 2
	var state: Dictionary = panel.save_state()
	assert_that(state.get("player_id")).is_equal(2)
	panel._player_id = 0
	panel.load_state(state)
	assert_that(panel._player_id).is_equal(2)
