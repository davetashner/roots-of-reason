extends Node2D
## Main prototype scene — assembles map, camera, units, input, and HUD
## programmatically at runtime.

signal knowledge_burned(attacker_id: int, defender_id: int, regressed_techs: Array)

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const ProductionQueueScript := preload("res://scripts/prototype/production_queue.gd")
const AIEconomyScript := preload("res://scripts/ai/ai_economy.gd")
const AIMilitaryScript := preload("res://scripts/ai/ai_military.gd")
const AITechScript := preload("res://scripts/ai/ai_tech.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")
const WolfAIScript := preload("res://scripts/fauna/wolf_ai.gd")
const DogAIScript := preload("res://scripts/fauna/dog_ai.gd")
const RiverTransportScript := preload("res://scripts/prototype/river_transport.gd")
const TradeManagerScript := preload("res://scripts/prototype/trade_manager.gd")
const TradeCartAIScript := preload("res://scripts/prototype/trade_cart_ai.gd")
const NotificationPanelScript := preload("res://scripts/ui/notification_panel.gd")
const RiverOverlayScript := preload("res://scripts/ui/river_overlay.gd")
const VictoryManagerScript := preload("res://scripts/prototype/victory_manager.gd")
const KnowledgeBurningVFXScript := preload("res://scripts/prototype/knowledge_burning_vfx.gd")
const WarSurvivalScript := preload("res://scripts/prototype/war_survival.gd")
const VictoryScreenScript := preload("res://scripts/ui/victory_screen.gd")
const TechTreeViewerScript := preload("res://scripts/ui/tech_tree_viewer.gd")
const SingularityRegressionScript := preload("res://scripts/prototype/singularity_regression.gd")
const AISingularityScript := preload("res://scripts/ai/ai_singularity.gd")
const SingularityCinematicVFXScript := preload("res://scripts/prototype/singularity_cinematic_vfx.gd")
const CivSelectionScreenScript := preload("res://scripts/ui/civ_selection_screen.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const MinimapScript := preload("res://scripts/ui/minimap.gd")
const PirateManagerScript := preload("res://scripts/prototype/pirate_manager.gd")

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
var _pending_victory_tech: Array = []


func _ready() -> void:
	_setup_map()
	_setup_fog_of_war()
	_setup_camera()
	_setup_pathfinding()
	_setup_target_detection()
	_setup_input()
	_setup_building_placer()
	_setup_population()
	# If civs are pre-set (launched from menu), skip selection and start directly
	if GameManager.get_player_civilization(0) != "":
		_start_game()
	else:
		_show_civ_selection()


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
	_setup_civilizations()
	_setup_units()
	_setup_demo_entities()
	_setup_fauna()
	_setup_tech()
	_setup_corruption()
	_setup_victory()
	_setup_river_transport()
	_setup_trade()
	_setup_ai()
	_setup_pirates()
	_setup_hud()
	# Initial visibility update after all units are placed
	_update_fog_of_war()


func _setup_map() -> void:
	var map_layer := TileMapLayer.new()
	map_layer.name = "Map"
	map_layer.set_script(load("res://scripts/map/tilemap_terrain.gd"))
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
	add_child(_fog_layer)
	_fog_layer.setup(dims.x, dims.y, 0)

	_visibility_manager.visibility_changed.connect(_on_visibility_changed)


func _update_fog_of_war() -> void:
	if _visibility_manager == null:
		return
	var player_units: Array = []
	for child in get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child:
			continue
		if child.owner_id != 0:
			continue
		if "hp" in child and child.hp <= 0:
			continue
		# Include buildings with dog LOS bonus
		if child.has_method("get_los") and child.get_los() > 0:
			player_units.append(child)
			continue
		# Include normal units
		if child.has_method("get_stat"):
			player_units.append(child)
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
	# Compute map bounds from corner grid positions and pass to camera
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


func _setup_pathfinding() -> void:
	_pathfinder = Node.new()
	_pathfinder.name = "PathfindingGrid"
	_pathfinder.set_script(load("res://scripts/prototype/pathfinding_grid.gd"))
	add_child(_pathfinder)
	_pathfinder.build(_map_node.get_map_size(), _map_node.get_tile_grid(), {})


func _setup_target_detection() -> void:
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


func _setup_population() -> void:
	_population_manager = Node.new()
	_population_manager.name = "PopulationManager"
	_population_manager.set_script(load("res://scripts/prototype/population_manager.gd"))
	add_child(_population_manager)


func _setup_building_placer() -> void:
	_building_placer = Node.new()
	_building_placer.name = "BuildingPlacer"
	_building_placer.set_script(load("res://scripts/prototype/building_placer.gd"))
	add_child(_building_placer)
	_building_placer.setup(_camera, _pathfinder, _map_node, _target_detector)
	_building_placer.building_placed.connect(_on_building_placed)


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
	# Don't open pause menu if victory screen is visible
	if _victory_screen != null and _victory_screen.visible:
		return
	if _pause_menu.visible:
		_pause_menu.hide_menu()
	else:
		_pause_menu.show_menu()


func _setup_civilizations() -> void:
	var player_civ: String = GameManager.get_player_civilization(0)
	var ai_civ: String = GameManager.get_player_civilization(1)
	if player_civ == "":
		player_civ = "mesopotamia"
	if ai_civ == "":
		ai_civ = "rome"
	CivBonusManager.apply_civ_bonuses(0, player_civ)
	CivBonusManager.apply_civ_bonuses(1, ai_civ)
	CivBonusManager.apply_starting_bonuses(0)
	CivBonusManager.apply_starting_bonuses(1)


func _setup_units() -> void:
	var offsets := _get_villager_offsets()
	var tc_pos := _get_player_start_position()
	for i in offsets.size():
		var unit := Node2D.new()
		unit.name = "Unit_%d" % i
		unit.set_script(UnitScript)
		var offset: Vector2i = offsets[i]
		var spawn_pos: Vector2i = tc_pos + offset
		unit.position = IsoUtils.grid_to_screen(Vector2(spawn_pos))
		unit.unit_type = "villager"
		add_child(unit)
		unit._scene_root = self
		if _visibility_manager != null:
			unit._visibility_manager = _visibility_manager
		if _war_survival != null:
			unit._war_survival = _war_survival
		# Register with input handler after both are in tree
		if _input_handler.has_method("register_unit"):
			_input_handler.register_unit(unit)
		if _target_detector != null:
			_target_detector.register_entity(unit)
		if _population_manager != null:
			_population_manager.register_unit(unit, 0)
		unit.unit_died.connect(_on_unit_died)


func _setup_demo_entities() -> void:
	# Resource nodes — generated by map system
	var all_resource_positions: Dictionary = _map_node.get_resource_positions()

	var res_index := 0
	for res_name: String in all_resource_positions:
		var positions: Array = all_resource_positions[res_name]
		for pos in positions:
			var grid_pos: Vector2i = pos as Vector2i
			var res_node := Node2D.new()
			res_node.name = "Resource_%s_%d" % [res_name, res_index]
			res_node.set_script(ResourceNodeScript)
			res_node.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
			add_child(res_node)
			res_node.setup(res_name)
			res_node.depleted.connect(_on_resource_depleted)
			res_node.regen_started.connect(_on_resource_regen_started)
			_target_detector.register_entity(res_node)
			res_index += 1
	# Own building (blue, 3x3 town center) — fully built
	var building := Node2D.new()
	building.name = "Building_0"
	building.set_script(BuildingScript)
	var bld_pos := _get_player_start_position()
	building.position = IsoUtils.grid_to_screen(Vector2(bld_pos))
	building.owner_id = 0
	building.building_name = "town_center"
	building.footprint = Vector2i(3, 3)
	building.grid_pos = bld_pos
	building.hp = 2400
	building.max_hp = 2400
	building.under_construction = false
	building.build_progress = 1.0
	add_child(building)
	_target_detector.register_entity(building)
	if _population_manager != null:
		_population_manager.register_building(building, building.owner_id)
	building.building_destroyed.connect(_on_building_destroyed)
	_try_attach_production_queue(building)
	# Mark footprint cells solid
	var cells := BuildingValidator.get_footprint_cells(bld_pos, Vector2i(3, 3))
	for cell in cells:
		_pathfinder.set_cell_solid(cell, true)


func _setup_fauna() -> void:
	var all_fauna: Dictionary = _map_node.get_fauna_positions()
	var fauna_index := 0
	var pack_index := 0
	for fauna_name: String in all_fauna:
		var packs: Array = all_fauna[fauna_name]
		for pack in packs:
			var pack_dict: Dictionary = pack as Dictionary
			var grid_pos: Vector2i = pack_dict.get("position", Vector2i.ZERO)
			var pack_size: int = int(pack_dict.get("pack_size", 2))
			for i in pack_size:
				var unit := Node2D.new()
				unit.name = "Fauna_%s_%d" % [fauna_name, fauna_index]
				unit.set_script(UnitScript)
				# Offset pack members slightly
				var offset := Vector2i(i % 2, i / 2)
				var spawn_pos: Vector2i = grid_pos + offset
				unit.position = IsoUtils.grid_to_screen(Vector2(spawn_pos))
				unit.unit_type = fauna_name
				unit.owner_id = -1  # Gaia faction
				unit.unit_color = Color(0.5, 0.5, 0.5)  # Gray
				add_child(unit)
				unit._scene_root = self
				if _war_survival != null:
					unit._war_survival = _war_survival
				if _target_detector != null:
					_target_detector.register_entity(unit)
				# Set entity category for wild fauna
				if fauna_name == "wolf":
					unit.entity_category = "wild_fauna"
				# Attach wolf AI for wolf fauna
				if fauna_name == "wolf":
					var wolf_ai := Node.new()
					wolf_ai.name = "WolfAI"
					wolf_ai.set_script(WolfAIScript)
					wolf_ai.pack_id = pack_index
					unit.add_child(wolf_ai)
					wolf_ai.domesticated.connect(func(foid: int) -> void: _on_wolf_domesticated(unit, foid))
				# Connect death signal for carcass spawning
				if unit.has_signal("unit_died"):
					unit.unit_died.connect(_on_fauna_died)
				fauna_index += 1
			pack_index += 1


func _on_wolf_domesticated(wolf_unit: Node2D, feeder_owner_id: int) -> void:
	wolf_unit.owner_id = feeder_owner_id
	wolf_unit.entity_category = "dog"
	wolf_unit.unit_color = Color(0.6, 0.4, 0.2)  # Brown
	# Remove WolfAI and attach DogAI
	var wolf_ai := wolf_unit.get_node_or_null("WolfAI")
	if wolf_ai != null:
		wolf_unit.remove_child(wolf_ai)
		wolf_ai.queue_free()
	# Reinit stats to dog type
	wolf_unit.unit_type = "dog"
	wolf_unit._init_stats()
	# Create DogAI
	var dog_ai := Node.new()
	dog_ai.name = "DogAI"
	dog_ai.set_script(DogAIScript)
	wolf_unit.add_child(dog_ai)
	dog_ai.danger_alert.connect(_on_dog_danger_alert)
	wolf_unit.queue_redraw()
	if _input_handler != null and _input_handler.has_method("register_unit"):
		_input_handler.register_unit(wolf_unit)


func _on_dog_danger_alert(_alert_position: Vector2, _player_id: int) -> void:
	# Stub for future minimap ping / audio bark integration
	pass


func _on_building_placed(building: Node2D) -> void:
	if building.has_signal("construction_complete"):
		building.construction_complete.connect(_on_building_construction_complete)
	if building.has_signal("building_destroyed"):
		building.building_destroyed.connect(_on_building_destroyed)
	var idle_unit := _find_nearest_idle_unit(building.global_position)
	if idle_unit != null and idle_unit.has_method("assign_build_target"):
		idle_unit.assign_build_target(building)


func _on_building_construction_complete(building: Node2D) -> void:
	if _population_manager != null and "owner_id" in building:
		_population_manager.register_building(building, building.owner_id)
	_try_attach_production_queue(building)


func _on_building_destroyed(building: Node2D) -> void:
	if _population_manager != null and "owner_id" in building:
		_population_manager.unregister_building(building, building.owner_id)
	if _target_detector != null:
		_target_detector.unregister_entity(building)
	# Release footprint cells from pathfinder
	if _pathfinder != null and "grid_pos" in building and "footprint" in building:
		var cells := BuildingValidator.get_footprint_cells(building.grid_pos, building.footprint)
		for cell in cells:
			_pathfinder.set_cell_solid(cell, false)
	# Knowledge burning: destroying a completed town center triggers tech regression
	if (
		building.building_name == "town_center"
		and not building.under_construction
		and building.last_attacker_id >= 0
		and building.last_attacker_id != building.owner_id
	):
		var regressed: Array = _tech_manager.trigger_knowledge_burning(building.owner_id)
		if not regressed.is_empty():
			knowledge_burned.emit(building.last_attacker_id, building.owner_id, regressed)
			_play_knowledge_burning_vfx(building.position, building.owner_id, building.last_attacker_id, regressed)
	# Notify AI brains of building destruction
	if "owner_id" in building and int(building.owner_id) == 1:
		if _ai_military != null:
			_ai_military.on_building_destroyed(building)
		if _ai_economy != null:
			_ai_economy.on_building_destroyed(building)
	_update_fog_of_war()


func _play_knowledge_burning_vfx(
	world_pos: Vector2,
	defender_id: int,
	attacker_id: int,
	regressed_techs: Array,
) -> void:
	if _knowledge_burning_vfx == null:
		return
	for tech_data: Dictionary in regressed_techs:
		var tech_name: String = tech_data.get("name", "Unknown Technology")
		var effects: Dictionary = tech_data.get("effects", {})
		var desc: String = _format_tech_effect_description(effects)
		_knowledge_burning_vfx.play_burning_effect(world_pos, tech_name, desc, defender_id, attacker_id)


func _format_tech_effect_description(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in effects:
		var value: Variant = effects[key]
		if value is float or value is int:
			var sign: String = "+" if float(value) >= 0.0 else ""
			parts.append("%s%s %s" % [sign, str(value), key.replace("_", " ")])
		else:
			parts.append("%s: %s" % [key.replace("_", " "), str(value)])
	if parts.is_empty():
		return "unknown effect"
	return ", ".join(parts)


func _setup_victory() -> void:
	_victory_manager = Node.new()
	_victory_manager.name = "VictoryManager"
	_victory_manager.set_script(VictoryManagerScript)
	add_child(_victory_manager)
	_victory_manager.setup(_building_placer)
	# Register existing player TC (created in _setup_demo_entities)
	for child in get_children():
		if "building_name" in child and child.building_name == "town_center":
			if not child.under_construction:
				_victory_manager.register_town_center(child.owner_id, child)
	# Connect victory/defeat signals
	_victory_manager.player_defeated.connect(_on_player_defeated)
	_victory_manager.player_victorious.connect(_on_player_victorious)
	_victory_manager.agi_core_built.connect(_on_agi_core_built)
	_victory_manager.wonder_countdown_started.connect(_on_wonder_countdown_started)
	_victory_manager.wonder_countdown_cancelled.connect(_on_wonder_countdown_cancelled)
	# Connect age advancement for singularity check
	GameManager.age_advanced.connect(_victory_manager.on_age_advanced)


func _on_player_defeated(player_id: int) -> void:
	if player_id == 0 and _victory_screen != null:
		_victory_screen.show_defeat("All Town Centers Lost")


func _on_player_victorious(player_id: int, condition: String) -> void:
	if player_id == 0 and _victory_screen != null:
		var result: Dictionary = _victory_manager.get_game_result()
		var label: String = result.get("condition_label", condition)
		_victory_screen.show_victory(label)


func _on_victory_tech_completed(player_id: int, tech_id: String) -> void:
	if player_id == 0 and _singularity_cinematic != null:
		_pending_victory_tech = [player_id, tech_id]
		get_tree().paused = true
		_singularity_cinematic.process_mode = Node.PROCESS_MODE_ALWAYS
		_singularity_cinematic.play_cinematic()
		_singularity_cinematic.cinematic_complete.connect(_on_singularity_cinematic_complete, CONNECT_ONE_SHOT)
	else:
		_victory_manager.on_victory_tech_completed(player_id, tech_id)


func _on_singularity_cinematic_complete() -> void:
	get_tree().paused = false
	if not _pending_victory_tech.is_empty():
		var pid: int = int(_pending_victory_tech[0])
		var tid: String = str(_pending_victory_tech[1])
		_pending_victory_tech = []
		_victory_manager.on_victory_tech_completed(pid, tid)


func _on_agi_core_built(player_id: int) -> void:
	if player_id == 0 and _singularity_cinematic != null:
		get_tree().paused = true
		_singularity_cinematic.process_mode = Node.PROCESS_MODE_ALWAYS
		_singularity_cinematic.play_cinematic()
		_singularity_cinematic.cinematic_complete.connect(
			func() -> void:
				get_tree().paused = false
				_victory_manager._trigger_victory(player_id, "singularity"),
			CONNECT_ONE_SHOT,
		)
	else:
		_victory_manager._trigger_victory(player_id, "singularity")


func _on_wonder_countdown_started(_player_id: int, duration: float) -> void:
	if _notification_panel == null:
		return
	var minutes: int = int(duration) / 60
	_notification_panel.notify("A Wonder has been completed! %d minutes remain." % minutes, "alert")


func _on_wonder_countdown_cancelled(_player_id: int) -> void:
	if _notification_panel == null:
		return
	_notification_panel.notify("Wonder destroyed! Countdown cancelled.", "alert")


func _setup_river_transport() -> void:
	_river_transport = Node.new()
	_river_transport.name = "RiverTransport"
	_river_transport.set_script(RiverTransportScript)
	add_child(_river_transport)
	_river_transport.setup(_map_node, _building_placer, _target_detector)
	# Connect destruction signals for notifications
	_river_transport.barge_destroyed_with_resources.connect(_on_barge_destroyed_with_resources)


func _setup_trade() -> void:
	_trade_manager = Node.new()
	_trade_manager.name = "TradeManager"
	_trade_manager.set_script(TradeManagerScript)
	add_child(_trade_manager)
	_trade_manager.setup(_building_placer)


func _on_barge_destroyed_with_resources(barge: Node2D, resources: Dictionary) -> void:
	if _notification_panel == null:
		return
	if barge.owner_id != 0:
		return
	var total: int = 0
	for res_type: int in resources:
		total += resources[res_type]
	if total > 0:
		_notification_panel.notify("Barge destroyed! Lost %d resources." % total, "alert")


func _setup_ai() -> void:
	var difficulty: String = GameManager.ai_difficulty
	var tier_config: Dictionary = _load_ai_tier_config(difficulty)
	ResourceManager.init_player(1, null, difficulty)
	var multiplier: float = tier_config.get("gather_rate_multiplier", 1.0)
	if not is_equal_approx(multiplier, 1.0):
		ResourceManager.set_gather_multiplier(1, multiplier)
	var ai_tc := _create_ai_town_center()
	var villager_count: int = tier_config.get("starting_villagers", 3)
	_create_ai_starting_villagers(ai_tc, villager_count)
	# Resolve gameplay personality
	var personality_id: String = str(tier_config.get("gameplay_personality", "random"))
	if personality_id == "random":
		personality_id = AIPersonality.get_random_id()
	var ai_pers: AIPersonality = AIPersonality.get_personality(personality_id)
	_ai_economy = Node.new()
	_ai_economy.name = "AIEconomy"
	_ai_economy.set_script(AIEconomyScript)
	_ai_economy.difficulty = difficulty
	_ai_economy.personality = ai_pers
	add_child(_ai_economy)
	_ai_economy.setup(self, _population_manager, _pathfinder, _map_node, _target_detector, _tech_manager)
	_ai_military = Node.new()
	_ai_military.name = "AIMilitary"
	_ai_military.set_script(AIMilitaryScript)
	_ai_military.difficulty = difficulty
	_ai_military.personality = ai_pers
	add_child(_ai_military)
	_ai_military.setup(self, _population_manager, _target_detector, _ai_economy, _tech_manager)
	_ai_tech = Node.new()
	_ai_tech.name = "AITech"
	_ai_tech.set_script(AITechScript)
	_ai_tech.difficulty = difficulty
	_ai_tech.gameplay_personality = ai_pers
	add_child(_ai_tech)
	_ai_tech.setup(_tech_manager)
	# Connect tech regression signals to AI brains
	_tech_manager.tech_regressed.connect(_ai_military.on_tech_regressed)
	_tech_manager.tech_regressed.connect(_ai_tech.on_tech_regressed)
	# AI Singularity awareness
	_ai_singularity = Node.new()
	_ai_singularity.name = "AISingularity"
	_ai_singularity.set_script(AISingularityScript)
	_ai_singularity.difficulty = difficulty
	_ai_singularity.personality = ai_pers
	add_child(_ai_singularity)
	_ai_singularity.setup(_tech_manager, _ai_military, _ai_tech)


func _setup_pirates() -> void:
	_pirate_manager = Node.new()
	_pirate_manager.name = "PirateManager"
	_pirate_manager.set_script(PirateManagerScript)
	add_child(_pirate_manager)
	_pirate_manager.setup(self, _map_node, _target_detector, _tech_manager)


func _load_ai_tier_config(difficulty: String) -> Dictionary:
	var data: Dictionary = DataLoader.load_json("res://data/ai/ai_difficulty.json")
	if data == null:
		return {}
	var tiers: Dictionary = data.get("tiers", {})
	if difficulty in tiers:
		return tiers[difficulty]
	var default_tier: String = data.get("default", "normal")
	return tiers.get(default_tier, {})


func _create_ai_town_center() -> Node2D:
	var tc_pos := _get_ai_start_position()
	var building := Node2D.new()
	building.name = "AI_TownCenter"
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(tc_pos))
	building.owner_id = 1
	building.building_name = "town_center"
	building.footprint = Vector2i(3, 3)
	building.grid_pos = tc_pos
	building.hp = 2400
	building.max_hp = 2400
	building.under_construction = false
	building.build_progress = 1.0
	building.entity_category = "enemy_building"
	add_child(building)
	_target_detector.register_entity(building)
	if _population_manager != null:
		_population_manager.register_building(building, building.owner_id)
	building.building_destroyed.connect(_on_building_destroyed)
	_try_attach_production_queue(building)
	# Mark footprint cells solid
	var cells := BuildingValidator.get_footprint_cells(tc_pos, Vector2i(3, 3))
	for cell in cells:
		_pathfinder.set_cell_solid(cell, true)
	return building


func _create_ai_starting_villagers(tc: Node2D, count: int) -> void:
	var offsets := _get_villager_offsets()
	for i in count:
		var unit := Node2D.new()
		unit.name = "AIVillager_%d" % i
		unit.set_script(UnitScript)
		unit.unit_type = "villager"
		unit.owner_id = 1
		unit.unit_color = Color(0.9, 0.2, 0.2)
		var offset := offsets[i % offsets.size()]
		var spawn_pos: Vector2i = tc.grid_pos + offset
		unit.position = IsoUtils.grid_to_screen(Vector2(spawn_pos))
		add_child(unit)
		unit._scene_root = self
		if _war_survival != null:
			unit._war_survival = _war_survival
		if _target_detector != null:
			_target_detector.register_entity(unit)
		if _population_manager != null:
			_population_manager.register_unit(unit, 1)
		unit.unit_died.connect(_on_unit_died)


func _find_nearest_idle_unit(target_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for child in get_children():
		if not child.has_method("is_idle"):
			continue
		if "owner_id" in child and child.owner_id != 0:
			continue
		if not child.is_idle():
			continue
		var dist: float = child.global_position.distance_to(target_pos)
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


func _try_attach_production_queue(building: Node2D) -> void:
	if not "building_name" in building:
		return
	var building_name: String = building.building_name
	if building_name == "":
		return
	var stats: Dictionary = DataLoader.get_building_stats(building_name)
	var units_produced: Array = stats.get("units_produced", [])
	if units_produced.is_empty():
		return
	var pq := Node.new()
	pq.name = "ProductionQueue"
	pq.set_script(ProductionQueueScript)
	building.add_child(pq)
	var owner_id: int = building.owner_id if "owner_id" in building else 0
	pq.setup(building, owner_id, _population_manager)
	pq.unit_produced.connect(_on_unit_produced)


func _on_unit_produced(unit_type: String, building: Node2D) -> void:
	var unit := Node2D.new()
	var unit_count := get_child_count()
	unit.name = "Unit_%d" % unit_count
	unit.set_script(UnitScript)
	var owner_id: int = building.owner_id if "owner_id" in building else 0
	var resolved_type := CivBonusManager.get_resolved_unit_id(owner_id, unit_type)
	unit.unit_type = resolved_type
	unit.owner_id = owner_id
	# Spawn at building position offset by rally point
	var pq: Node = building.get_node_or_null("ProductionQueue")
	var offset := Vector2i(1, 1)
	if pq != null and pq.has_method("get_rally_point_offset"):
		offset = pq.get_rally_point_offset()
	var spawn_grid: Vector2i = Vector2i.ZERO
	if "grid_pos" in building:
		spawn_grid = building.grid_pos + offset
	# Naval units spawn on adjacent water tile instead of land
	var unit_stats: Dictionary = DataLoader.get_unit_stats(resolved_type)
	if unit_stats.get("movement_type", "") == "water" and _map_node != null:
		var naval_spawn := _find_naval_spawn_point(building)
		if naval_spawn != Vector2i(-1, -1):
			spawn_grid = naval_spawn
	unit.position = IsoUtils.grid_to_screen(Vector2(spawn_grid))
	add_child(unit)
	unit._scene_root = self
	if _visibility_manager != null:
		unit._visibility_manager = _visibility_manager
	if _war_survival != null:
		unit._war_survival = _war_survival
	if _input_handler != null and _input_handler.has_method("register_unit"):
		_input_handler.register_unit(unit)
	if _target_detector != null:
		_target_detector.register_entity(unit)
	if _population_manager != null:
		_population_manager.register_unit(unit, owner_id)
	if _unit_upgrade_manager != null:
		_unit_upgrade_manager.apply_upgrades_to_unit(unit, owner_id)
	CivBonusManager.apply_bonus_to_unit(unit.stats, unit.unit_type, owner_id)
	unit.unit_died.connect(_on_unit_died)
	# Attach trade AI for trade carts and merchant ships
	if unit_type == "trade_cart" or unit_type == "merchant_ship":
		var trade_ai := Node.new()
		trade_ai.name = "TradeCartAI"
		trade_ai.set_script(TradeCartAIScript)
		unit.add_child(trade_ai)


func _on_resource_depleted(node: Node2D) -> void:
	if _target_detector != null and _target_detector.has_method("unregister_entity"):
		_target_detector.unregister_entity(node)


func _on_resource_regen_started(_node: Node2D) -> void:
	pass


func _on_unit_died(unit: Node2D, _killer: Node2D) -> void:
	if _target_detector != null:
		_target_detector.unregister_entity(unit)
	if _population_manager != null and "owner_id" in unit:
		_population_manager.unregister_unit(unit, unit.owner_id)
	_update_fog_of_war()


func _on_fauna_died(unit: Node2D, _killer: Node2D) -> void:
	if _target_detector != null:
		_target_detector.unregister_entity(unit)
	# Spawn carcass for wolves
	if "unit_type" in unit and unit.unit_type == "wolf":
		_spawn_wolf_carcass(unit.global_position)
	_update_fog_of_war()


func _spawn_wolf_carcass(world_pos: Vector2) -> void:
	var res_node := Node2D.new()
	var carcass_index := get_child_count()
	res_node.name = "Resource_wolf_carcass_%d" % carcass_index
	res_node.set_script(ResourceNodeScript)
	res_node.position = world_pos
	add_child(res_node)
	res_node.setup("wolf_carcass")
	res_node.depleted.connect(_on_resource_depleted)
	if _target_detector != null:
		_target_detector.register_entity(res_node)


func _setup_tech() -> void:
	_tech_manager = Node.new()
	_tech_manager.name = "TechManager"
	_tech_manager.set_script(load("res://scripts/prototype/tech_manager.gd"))
	add_child(_tech_manager)
	# War research bonus node — tracks combat state and provides speed multiplier
	_war_bonus = Node.new()
	_war_bonus.name = "WarResearchBonus"
	_war_bonus.set_script(load("res://scripts/prototype/war_research_bonus.gd"))
	add_child(_war_bonus)
	_tech_manager.setup_war_bonus(_war_bonus)
	# Unit upgrade manager — applies tech stat_modifiers to units
	_unit_upgrade_manager = Node.new()
	_unit_upgrade_manager.name = "UnitUpgradeManager"
	_unit_upgrade_manager.set_script(load("res://scripts/prototype/unit_upgrade_manager.gd"))
	add_child(_unit_upgrade_manager)
	_unit_upgrade_manager.setup(self)
	_tech_manager.tech_researched.connect(_unit_upgrade_manager.on_tech_researched)
	_tech_manager.tech_regressed.connect(_unit_upgrade_manager.on_tech_regressed)
	# War survival — medical tech chain for lethal-damage survival
	_war_survival = Node.new()
	_war_survival.name = "WarSurvival"
	_war_survival.set_script(WarSurvivalScript)
	add_child(_war_survival)
	_war_survival.setup(_tech_manager)
	# Connect tech completion to spillover system
	_tech_manager.tech_researched.connect(_on_tech_researched_spillover)
	# Singularity regression — tech regression + singularity path interaction
	_singularity_regression = Node.new()
	_singularity_regression.name = "SingularityRegression"
	_singularity_regression.set_script(SingularityRegressionScript)
	add_child(_singularity_regression)
	_singularity_regression.setup(_tech_manager, _notification_panel)
	# Wire victory tech completion signal for singularity cinematic
	_tech_manager.victory_tech_completed.connect(_on_victory_tech_completed)
	# Provide tech_manager to building placer for prerequisite checks
	if _building_placer != null:
		_building_placer._tech_manager = _tech_manager


func _setup_corruption() -> void:
	_corruption_manager = Node.new()
	_corruption_manager.name = "CorruptionManager"
	_corruption_manager.set_script(load("res://scripts/prototype/corruption_manager.gd"))
	add_child(_corruption_manager)
	_corruption_manager.setup(_population_manager, _tech_manager)


func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/prototype/prototype_hud.gd"))
	add_child(hud)
	# Connect camera and input handler
	if hud.has_method("setup"):
		hud.setup(_camera, _input_handler)
	# Info panel for selected unit/building details
	var info_panel_layer := CanvasLayer.new()
	info_panel_layer.name = "InfoPanel"
	info_panel_layer.layer = 10
	add_child(info_panel_layer)
	_info_panel = PanelContainer.new()
	_info_panel.name = "InfoPanelWidget"
	_info_panel.set_script(load("res://scripts/ui/info_panel.gd"))
	info_panel_layer.add_child(_info_panel)
	_info_panel.setup(_input_handler, _target_detector, _river_transport, _trade_manager)
	# Command panel
	var cmd_panel_layer := CanvasLayer.new()
	cmd_panel_layer.name = "CommandPanel"
	cmd_panel_layer.layer = 10
	add_child(cmd_panel_layer)
	var cmd_panel := PanelContainer.new()
	cmd_panel.name = "CommandPanelWidget"
	cmd_panel.set_script(load("res://scripts/ui/command_panel.gd"))
	cmd_panel_layer.add_child(cmd_panel)
	cmd_panel.setup(_input_handler, _building_placer, _trade_manager)
	# Cursor overlay for command context labels
	_cursor_overlay = CanvasLayer.new()
	_cursor_overlay.name = "CursorOverlay"
	_cursor_overlay.set_script(load("res://scripts/prototype/cursor_overlay.gd"))
	add_child(_cursor_overlay)
	_input_handler._cursor_overlay = _cursor_overlay
	# Resource bar HUD
	_setup_resource_bar()
	# Notification panel (right side, scene-local)
	var notif_layer := CanvasLayer.new()
	notif_layer.name = "NotificationLayer"
	notif_layer.layer = 11
	add_child(notif_layer)
	_notification_panel = Control.new()
	_notification_panel.name = "NotificationPanel"
	_notification_panel.set_script(NotificationPanelScript)
	notif_layer.add_child(_notification_panel)
	# Knowledge burning VFX — wired to tech_regressed signal
	_knowledge_burning_vfx = Node.new()
	_knowledge_burning_vfx.name = "KnowledgeBurningVFX"
	_knowledge_burning_vfx.set_script(KnowledgeBurningVFXScript)
	add_child(_knowledge_burning_vfx)
	_knowledge_burning_vfx.setup(self, _camera, _notification_panel)
	# Singularity cinematic VFX — plays when AGI Core completes
	_singularity_cinematic = Node.new()
	_singularity_cinematic.name = "SingularityCinematicVFX"
	_singularity_cinematic.set_script(SingularityCinematicVFXScript)
	add_child(_singularity_cinematic)
	_singularity_cinematic.setup(self, _camera)
	# River overlay (sibling Node2D, higher z_index than tilemap)
	_river_overlay = Node2D.new()
	_river_overlay.name = "RiverOverlay"
	_river_overlay.set_script(RiverOverlayScript)
	_river_overlay.z_index = 5
	add_child(_river_overlay)
	_river_overlay.setup(_map_node, _get_player_start_position())
	# Wire input handler to river overlay
	_input_handler._river_overlay = _river_overlay
	# Victory/Defeat screen overlay
	var victory_layer := CanvasLayer.new()
	victory_layer.name = "VictoryLayer"
	victory_layer.layer = 20
	add_child(victory_layer)
	_victory_screen = PanelContainer.new()
	_victory_screen.name = "VictoryScreen"
	_victory_screen.set_script(VictoryScreenScript)
	victory_layer.add_child(_victory_screen)
	# Tech tree viewer overlay
	var tech_viewer_layer := CanvasLayer.new()
	tech_viewer_layer.name = "TechTreeViewerLayer"
	tech_viewer_layer.layer = 15
	add_child(tech_viewer_layer)
	_tech_tree_viewer = PanelContainer.new()
	_tech_tree_viewer.name = "TechTreeViewer"
	_tech_tree_viewer.set_script(TechTreeViewerScript)
	tech_viewer_layer.add_child(_tech_tree_viewer)
	_tech_tree_viewer.setup(_tech_manager, 0)
	# Pause menu overlay (above victory screen)
	var pause_layer := CanvasLayer.new()
	pause_layer.name = "PauseMenuLayer"
	pause_layer.layer = 22
	add_child(pause_layer)
	_pause_menu = PanelContainer.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.set_script(PauseMenuScript)
	pause_layer.add_child(_pause_menu)
	_pause_menu.quit_to_menu.connect(_on_pause_menu_quit_to_menu)
	_pause_menu.quit_to_desktop.connect(_on_pause_menu_quit_to_desktop)
	# Minimap (bottom-left)
	var minimap_layer := CanvasLayer.new()
	minimap_layer.name = "MinimapLayer"
	minimap_layer.layer = 10
	add_child(minimap_layer)
	_minimap = Control.new()
	_minimap.name = "Minimap"
	_minimap.set_script(MinimapScript)
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_minimap.position = Vector2(8, -208)
	minimap_layer.add_child(_minimap)
	_minimap.setup(_map_node, _camera, _visibility_manager, self)
	_minimap.minimap_move_command.connect(_on_minimap_move_command)


func _setup_resource_bar() -> void:
	ResourceManager.init_player(0)
	var resource_bar_layer := CanvasLayer.new()
	resource_bar_layer.name = "ResourceBar"
	resource_bar_layer.layer = 10
	add_child(resource_bar_layer)
	_resource_bar = PanelContainer.new()
	_resource_bar.name = "ResourceBarPanel"
	_resource_bar.set_script(load("res://scripts/ui/resource_bar.gd"))
	resource_bar_layer.add_child(_resource_bar)
	# Connect population manager to resource bar display
	if _population_manager != null:
		_population_manager.population_changed.connect(_on_population_changed)
		# Initial display update
		var current: int = _population_manager.get_population(0)
		var cap: int = _population_manager.get_population_cap(0)
		_resource_bar.update_population(current, cap)
	# Connect corruption display
	if _corruption_manager != null:
		_corruption_manager.corruption_changed.connect(_on_corruption_changed)
	# Connect river transport for in-transit resource display
	if _river_transport != null:
		_resource_bar.setup_transit(_river_transport)


func _on_tech_researched_spillover(player_id: int, tech_id: String, _effects: Dictionary) -> void:
	if _war_bonus != null:
		var tech_data: Dictionary = DataLoader.get_tech_data(tech_id)
		_war_bonus.apply_spillover(player_id, tech_id, tech_data)


func _on_corruption_changed(player_id: int, rate: float) -> void:
	if player_id == 0 and _resource_bar != null:
		_resource_bar.update_corruption(rate)


func _on_population_changed(player_id: int, current: int, cap: int) -> void:
	if player_id == 0 and _resource_bar != null:
		_resource_bar.update_population(current, cap)


func _on_pause_menu_quit_to_menu() -> void:
	GameManager.reset_game_state()
	ResourceManager.reset()
	CivBonusManager.reset()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_pause_menu_quit_to_desktop() -> void:
	get_tree().quit()


func _on_minimap_move_command(world_pos: Vector2) -> void:
	if _input_handler != null and _input_handler.has_method("_move_selected"):
		_input_handler._move_selected(world_pos)


func _find_naval_spawn_point(building: Node2D) -> Vector2i:
	if _map_node == null or not _map_node.has_method("get_terrain_at"):
		return Vector2i(-1, -1)
	var footprint := Vector2i(1, 1)
	if "footprint" in building:
		footprint = building.footprint
	var origin := Vector2i.ZERO
	if "grid_pos" in building:
		origin = building.grid_pos
	var cells := BuildingValidator.get_footprint_cells(origin, footprint)
	var water_terrains: Array[String] = ["water", "shallows", "deep_water"]
	var directions: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(1, 1),
	]
	for cell in cells:
		for dir in directions:
			var neighbor := cell + dir
			if neighbor in cells:
				continue
			if _map_node.get_terrain_at(neighbor) in water_terrains:
				return neighbor
	return Vector2i(-1, -1)


func _get_player_start_position() -> Vector2i:
	var positions: Array = _map_node.get_starting_positions()
	if positions.size() >= 1:
		return positions[0] as Vector2i
	return Vector2i(4, 4)


func _get_ai_start_position() -> Vector2i:
	var positions: Array = _map_node.get_starting_positions()
	if positions.size() >= 2:
		return positions[1] as Vector2i
	var map_size: int = _map_node.get_map_size()
	return Vector2i(map_size - 7, map_size - 7)


func _get_villager_offsets() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var map_gen_cfg: Dictionary = DataLoader.load_json("res://data/settings/map_generation.json")
	var start_cfg: Dictionary = map_gen_cfg.get("starting_locations", {})
	var raw_offsets: Array = start_cfg.get("villager_offsets", [[-1, 0], [0, -1], [-1, -1], [1, -1], [-1, 1]])
	for offset in raw_offsets:
		if offset is Array and offset.size() == 2:
			result.append(Vector2i(int(offset[0]), int(offset[1])))
	return result
