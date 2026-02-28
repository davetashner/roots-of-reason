extends Node2D
## Main prototype scene — coordinates bootstrapping, game flow, and scene lifecycle.
## Delegates setup to GameBootstrapper and event handling to GameFlowController.

const GameBootstrapperScript := preload("res://scripts/prototype/game_bootstrapper.gd")
const GameFlowControllerScript := preload("res://scripts/prototype/game_flow_controller.gd")
const SceneSaveHandlerScript := preload("res://scripts/prototype/scene_save_handler.gd")
const EntityRegistryScript := preload("res://scripts/prototype/entity_registry.gd")
const CivSelectionScreenScript := preload("res://scripts/ui/civ_selection_screen.gd")
const FOG_UPDATE_INTERVAL: float = 0.2  # Update fog every 200ms

var _camera: Camera2D
var _input_handler: Node
var _map_node: Node
var _pathfinder: Node
var _target_detector: Node
var _cursor_overlay: Node
var _building_placer: Node
var _info_panel: PanelContainer
var _population_manager: Node
var _resource_bar: PanelContainer
var _tech_manager: Node
var _war_bonus: Node
var _ai_economy: Node = null
var _ai_military: Node = null
var _ai_tech: Node = null
var _visibility_manager: Node = null
var _unit_upgrade_manager: Node = null
var _corruption_manager: Node = null
var _fog_layer: Node = null
var _river_transport: Node = null
var _trade_manager: Node = null
var _notification_panel: Control = null
var _river_overlay: Node2D = null
var _victory_manager: Node = null
var _war_survival: Node = null
var _victory_screen: PanelContainer = null
var _knowledge_burning_vfx: Node = null
var _tech_tree_viewer: PanelContainer = null
var _singularity_regression: Node = null
var _ai_singularity: Node = null
var _civ_selection_screen: PanelContainer = null
var _pause_menu: PanelContainer = null
var _minimap: Control = null
var _singularity_cinematic: Node = null
var _pirate_manager: Node = null
var _pandemic_manager: Node = null
var _pandemic_vfx: Node = null
var _historical_event_manager: Node = null
var _historical_event_vfx: Node = null
var _game_stats_tracker: Node = null
var _postgame_stats_screen: PanelContainer = null
var _save_handler: RefCounted = null
var _entity_registry: RefCounted = null
var _pending_victory_tech: Array = []

## Extracted components for setup and flow control.
var _bootstrapper: RefCounted = null
var _flow: RefCounted = null

var _fog_timer: float = 0.0


func _ready() -> void:
	_bootstrapper = GameBootstrapperScript.new()
	_bootstrapper.setup(self)
	_flow = GameFlowControllerScript.new()
	_flow.setup(self, _bootstrapper)

	_setup_map()
	_setup_fog_of_war()
	_setup_camera()
	_setup_pathfinding()
	_setup_input()
	_setup_building_placer()
	tree_exiting.connect(_on_tree_exiting)
	_apply_quick_start_args()
	if GameManager.get_player_civilization(0) != "":
		_start_game()
	else:
		_show_civ_selection()
	_print_orphan_count("after _ready")


func _apply_quick_start_args() -> void:
	var user_args := OS.get_cmdline_user_args()
	var idx := user_args.find("--quick-start")
	if idx == -1:
		return
	var civ := "mesopotamia"
	if idx + 1 < user_args.size() and not user_args[idx + 1].begins_with("--"):
		civ = user_args[idx + 1]
	if GameManager.get_player_civilization(0) == "":
		GameManager.set_player_civilization(0, civ)
	if GameManager.get_player_civilization(1) == "":
		GameManager.set_player_civilization(1, "rome")


func _process(delta: float) -> void:
	_fog_timer += delta
	if _fog_timer >= FOG_UPDATE_INTERVAL:
		_fog_timer -= FOG_UPDATE_INTERVAL
		_update_fog_of_war()


func _show_civ_selection() -> void:
	var civ_layer := CanvasLayer.new()
	civ_layer.name = "CivSelectionLayer"
	civ_layer.layer = 25
	add_child(civ_layer)
	_civ_selection_screen = PanelContainer.new()
	_civ_selection_screen.name = "CivSelectionScreen"
	_civ_selection_screen.set_script(CivSelectionScreenScript)
	civ_layer.add_child(_civ_selection_screen)
	_civ_selection_screen.civ_selected.connect(_on_civ_selected)
	_civ_selection_screen.show_screen()


func _on_civ_selected(player_civ: String, ai_civ: String) -> void:
	GameManager.set_player_civilization(0, player_civ)
	GameManager.set_player_civilization(1, ai_civ)
	_start_game()


func _start_game() -> void:
	ResourceManager.init_player(0, null, GameManager.player_difficulty)  # Must precede setup_civilizations()
	ResourceManager.init_player(1, null, GameManager.ai_difficulty)
	_entity_registry = EntityRegistryScript.new()
	_bootstrapper.setup_civilizations()
	_bootstrapper.setup_units()
	_center_camera_on_start()
	_bootstrapper.setup_demo_entities()
	_bootstrapper.setup_fauna()
	_bootstrapper.setup_tech()
	_bootstrapper.setup_corruption()
	_bootstrapper.setup_pandemic()
	_bootstrapper.setup_historical_events()
	_bootstrapper.setup_victory()
	_bootstrapper.setup_river_transport()
	_bootstrapper.setup_trade()
	_bootstrapper.setup_ai()
	_bootstrapper.setup_pirates()
	_bootstrapper.setup_game_stats_tracker()
	_bootstrapper.setup_hud()
	_update_fog_of_war()
	_save_handler = SceneSaveHandlerScript.new()
	_save_handler.setup(self)
	SaveManager.register_scene_provider(self)
	tree_exiting.connect(func() -> void: SaveManager.register_scene_provider(null))
	_print_orphan_count("after _start_game")


# -- Save / load -------------------------------------------------------------


func save_state() -> Dictionary:
	if _save_handler != null:
		return _save_handler.save_state()
	return {}


func load_state(data: Dictionary) -> void:
	if _save_handler != null:
		await _save_handler.load_state(data)


# -- Cleanup -----------------------------------------------------------------


func _on_tree_exiting() -> void:
	_print_orphan_count("tree_exiting (before cleanup)")
	# Release RefCounted helpers so they drop _root references before
	# the scene tree tears children down.
	_bootstrapper = null
	_flow = null
	_save_handler = null
	_entity_registry = null
	# Explicitly free all children now, before Godot's default teardown.
	# This prevents shutdown ordering issues from leaving orphaned nodes.
	var count := get_child_count()
	for i in range(count - 1, -1, -1):
		var child := get_child(i)
		if is_instance_valid(child):
			child.free()
	_print_orphan_count("tree_exiting (after cleanup)")


static func _print_orphan_count(label: String) -> void:
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if orphans > 0:
		print("[leak-debug] %s: %d orphan node(s)" % [label, orphans])


# -- Infrastructure setup (runs before game start) ---------------------------


func _setup_map() -> void:
	var map_layer := TileMapLayer.new()
	map_layer.name = "Map"
	map_layer.set_script(load("res://scripts/map/tilemap_terrain.gd"))
	map_layer.z_index = 0
	# Offset so Godot's tile centers align with IsoUtils top-corner coords
	map_layer.position = Vector2(-IsoUtils.HALF_W, -IsoUtils.HALF_H)
	add_child(map_layer)
	_map_node = map_layer


func _setup_fog_of_war() -> void:
	var dims: Vector2i = _map_node.get_map_dimensions()
	var blocks_fn := func(pos: Vector2i) -> bool: return _map_node.blocks_los(pos)

	_visibility_manager = Node.new()
	_visibility_manager.name = "VisibilityManager"
	_visibility_manager.set_script(load("res://scripts/prototype/visibility_manager.gd"))
	add_child(_visibility_manager)
	_visibility_manager.setup(dims.x, dims.y, blocks_fn)

	_fog_layer = TileMapLayer.new()
	_fog_layer.name = "FogOfWar"
	_fog_layer.set_script(load("res://scripts/map/fog_of_war_layer.gd"))
	_fog_layer.z_index = 10
	# Offset so Godot's tile centers align with IsoUtils top-corner coords
	_fog_layer.position = Vector2(-IsoUtils.HALF_W, -IsoUtils.HALF_H)
	add_child(_fog_layer)
	_fog_layer.setup(dims.x, dims.y, 0)

	_visibility_manager.visibility_changed.connect(_on_visibility_changed)


func _update_fog_of_war() -> void:
	if _visibility_manager == null or _entity_registry == null:
		return
	var player_units: Array = []
	for entity in _entity_registry.get_by_owner(0):
		if "hp" in entity and entity.hp <= 0:
			continue
		if entity.has_method("get_los") and entity.get_los() > 0:
			player_units.append(entity)
			continue
		if entity.has_method("get_stat"):
			player_units.append(entity)
	_visibility_manager.update_visibility(0, player_units)


func _on_visibility_changed(player_id: int) -> void:
	if player_id != 0 or _fog_layer == null or _visibility_manager == null:
		return
	(
		_fog_layer
		. update_fog(
			_visibility_manager.get_visible_tiles(0),
			_visibility_manager.get_explored_tiles(0),
			_visibility_manager.get_prev_visible_tiles(0),
		)
	)


func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.set_script(load("res://scripts/prototype/prototype_camera.gd"))
	var map_size: int = _map_node.get_map_size()
	var half_size := map_size / 2
	var center := IsoUtils.grid_to_screen(Vector2(half_size, half_size))
	_camera.position = center
	_camera.enabled = true
	add_child(_camera)
	var corners: Array[Vector2] = [
		IsoUtils.grid_to_screen(Vector2(0, 0)),
		IsoUtils.grid_to_screen(Vector2(map_size, 0)),
		IsoUtils.grid_to_screen(Vector2(0, map_size)),
		IsoUtils.grid_to_screen(Vector2(map_size, map_size)),
	]
	var min_pos := corners[0]
	var max_pos := corners[0]
	for corner in corners:
		min_pos.x = minf(min_pos.x, corner.x)
		min_pos.y = minf(min_pos.y, corner.y)
		max_pos.x = maxf(max_pos.x, corner.x)
		max_pos.y = maxf(max_pos.y, corner.y)
	var bounds := Rect2(min_pos, max_pos - min_pos)
	_camera.setup(bounds)


func _center_camera_on_start() -> void:
	var start_pos: Vector2i = _bootstrapper.get_start_position(0)
	_camera.position = IsoUtils.grid_to_screen(Vector2(start_pos))


func _setup_pathfinding() -> void:
	_pathfinder = Node.new()
	_pathfinder.name = "PathfindingGrid"
	_pathfinder.set_script(load("res://scripts/prototype/pathfinding_grid.gd"))
	add_child(_pathfinder)
	_pathfinder.build(_map_node.get_map_size(), _map_node.get_tile_grid(), {})
	_target_detector = Node.new()
	_target_detector.name = "TargetDetector"
	_target_detector.set_script(load("res://scripts/prototype/target_detector.gd"))
	add_child(_target_detector)
	if _visibility_manager != null:
		_target_detector.set_visibility_manager(_visibility_manager)


func _setup_input() -> void:
	_input_handler = Node.new()
	_input_handler.name = "InputHandler"
	_input_handler.set_script(load("res://scripts/prototype/prototype_input.gd"))
	add_child(_input_handler)
	if _input_handler.has_method("setup"):
		_input_handler.setup(_camera, _pathfinder, _target_detector)


func _setup_building_placer() -> void:
	_population_manager = Node.new()
	_population_manager.name = "PopulationManager"
	_population_manager.set_script(load("res://scripts/prototype/population_manager.gd"))
	add_child(_population_manager)
	_building_placer = Node.new()
	_building_placer.name = "BuildingPlacer"
	_building_placer.set_script(load("res://scripts/prototype/building_placer.gd"))
	add_child(_building_placer)
	_building_placer.setup(_camera, _pathfinder, _map_node, _target_detector)
	_building_placer.building_placed.connect(_on_building_placed)


# -- Input handling ----------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE:
				_toggle_pause_menu()
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_B:
				if _building_placer != null and not _building_placer.is_active():
					_building_placer.start_placement("house", 0)
			elif key.keycode == KEY_T:
				if _tech_tree_viewer != null:
					_tech_tree_viewer.toggle_visible()


func _toggle_pause_menu() -> void:
	if _pause_menu == null:
		return
	if _victory_screen != null and _victory_screen.visible:
		return
	if _pause_menu.visible:
		_pause_menu.hide_menu()
	else:
		_pause_menu.show_menu()


# -- Flow controller delegation (public API kept on root for signal compat) --


func _on_building_placed(building: Node2D) -> void:
	_flow.on_building_placed(building)


func _on_building_construction_complete(building: Node2D) -> void:
	_flow.on_building_construction_complete(building)


func _on_building_destroyed(building: Node2D) -> void:
	_flow.on_building_destroyed(building)


func _on_unit_produced(unit_type: String, building: Node2D) -> void:
	_flow.on_unit_produced(unit_type, building)


func _on_unit_died(unit: Node2D, killer: Node2D) -> void:
	_flow.on_unit_died(unit, killer)


func _on_fauna_died(unit: Node2D, killer: Node2D) -> void:
	_flow.on_fauna_died(unit, killer)


func _on_resource_depleted(node: Node2D) -> void:
	_flow.on_resource_depleted(node)


func _on_wolf_domesticated(wolf_unit: Node2D, feeder_owner_id: int) -> void:
	_flow.on_wolf_domesticated(wolf_unit, feeder_owner_id)


func _on_dog_danger_alert(alert_position: Vector2, player_id: int) -> void:
	_flow.on_dog_danger_alert(alert_position, player_id)


func _on_player_defeated(player_id: int) -> void:
	_flow.on_player_defeated(player_id)


func _on_player_victorious(player_id: int, condition: String) -> void:
	_flow.on_player_victorious(player_id, condition)


func _on_victory_stats_pressed() -> void:
	_flow.on_victory_stats_pressed()


func _on_victory_tech_completed(player_id: int, tech_id: String) -> void:
	_flow.on_victory_tech_completed(player_id, tech_id)


func _on_agi_core_built(player_id: int) -> void:
	_flow.on_agi_core_built(player_id)


func _on_wonder_countdown_started(player_id: int, duration: float) -> void:
	_flow.on_wonder_countdown_started(player_id, duration)


func _on_wonder_countdown_cancelled(player_id: int) -> void:
	_flow.on_wonder_countdown_cancelled(player_id)


func _on_pandemic_started(player_id: int, severity: float) -> void:
	_flow.on_pandemic_started(player_id, severity)


func _on_pandemic_ended(player_id: int) -> void:
	_flow.on_pandemic_ended(player_id)


func _on_hist_event_started(event_id: String, player_id: int) -> void:
	_flow.on_hist_event_started(event_id, player_id)


func _on_hist_event_ended(event_id: String, player_id: int) -> void:
	_flow.on_hist_event_ended(event_id, player_id)


func _on_barge_destroyed_with_resources(barge: Node2D, resources: Dictionary) -> void:
	_flow.on_barge_destroyed_with_resources(barge, resources)


func _on_tech_researched_spillover(player_id: int, tech_id: String, effects: Dictionary) -> void:
	_flow.on_tech_researched_spillover(player_id, tech_id, effects)


func _on_corruption_changed(player_id: int, rate: float) -> void:
	_flow.on_corruption_changed(player_id, rate)


func _on_population_changed(player_id: int, current: int, cap: int) -> void:
	_flow.on_population_changed(player_id, current, cap)


func _on_pause_menu_quit_to_menu() -> void:
	_flow.on_pause_menu_quit_to_menu()


func _on_pause_menu_quit_to_desktop() -> void:
	_flow.on_pause_menu_quit_to_desktop()


func _on_minimap_move_command(world_pos: Vector2) -> void:
	_flow.on_minimap_move_command(world_pos)


func _on_singularity_cinematic_complete() -> void:
	_flow.on_singularity_cinematic_complete()
